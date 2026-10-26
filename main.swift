// Jelly Dock — 一个带果冻形变的 Dock 替代品
// 每个图标两根阻尼弹簧：shear（底边锚定、顶部甩动）和 squash（体积守恒的挤压拉伸），
// 相邻图标的 shear 之间有耦合，鼠标划过会激起一串波。
import AppKit
import QuartzCore

// MARK: - 参数

let iconSize: CGFloat = 56
let gap: CGFloat = 10
let pad: CGFloat = 10
let headroom: CGFloat = 48           // 果冻拉伸 + 名称标签的空间

let shearK: CGFloat = 260, shearC: CGFloat = 3.6, coupling: CGFloat = 90
let squashK: CGFloat = 300, squashC: CGFloat = 5.0
// 自己跳：所有图标同步连续上下起伏（只挤压/拉伸，不倾斜）
let beatHz: CGFloat = 2.2          // 起伏频率（次/秒）
let beatAmp: CGFloat = 0.12        // 最大形变 12%
func jellyCurve(_ t: CGFloat) -> CGFloat {
    beatAmp * sin(2 * .pi * beatHz * t)
}

// MARK: - 图标

final class Tile {
    let url: URL
    let layer = CALayer()
    let dot = CALayer()
    var running = false
    var s: CGFloat = 0, vs: CGFloat = 0   // shear
    var q: CGFloat = 0, vq: CGFloat = 0   // squash
    var centerX: CGFloat = 0

    init(url: URL, scale: CGFloat) {
        self.url = url
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: iconSize, height: iconSize)
        layer.contents = img.layerContents(forContentsScale: scale)
        layer.contentsScale = scale
        layer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        dot.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        dot.cornerRadius = 2
        dot.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
    }

    var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }

    func render(extra: CGFloat = 0) {
        let sy = 1 + q + extra
        let sx = 1 / max(sy, 0.3)          // 面积守恒
        layer.setAffineTransform(CGAffineTransform(a: sx, b: 0, c: s, d: sy, tx: 0, ty: 0))
    }
}

// MARK: - 图标层视图

final class IconsView: NSView {
    var tiles: [Tile] = []
    var hovered: Tile?
    var pressed: Tile?
    var lastMouse: (x: CGFloat, t: CFTimeInterval)?
    var lastStep = CACurrentMediaTime()
    let label = CATextLayer()
    var link: CADisplayLink?
    var clock: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        label.fontSize = 12
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.foregroundColor = NSColor.white.cgColor
        label.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.cornerRadius = 6
        label.alignmentMode = .center
        label.isHidden = true
        layer!.addSublayer(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func startLink() {
        link = displayLink(target: self, selector: #selector(frame(_:)))
        link?.add(to: .main, forMode: .common)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    func layout(tiles new: [Tile]) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for t in tiles where !new.contains(where: { $0 === t }) {
            t.layer.removeFromSuperlayer(); t.dot.removeFromSuperlayer()
        }
        tiles = new
        for (i, t) in tiles.enumerated() {
            if t.layer.superlayer == nil { layer!.insertSublayer(t.layer, below: label); layer!.addSublayer(t.dot) }
            t.centerX = pad + iconSize / 2 + CGFloat(i) * (iconSize + gap)
            t.layer.position = CGPoint(x: t.centerX, y: pad)
            t.dot.position = CGPoint(x: t.centerX, y: pad - 5)
            t.dot.isHidden = !t.running
            t.render()
        }
        CATransaction.commit()
    }

    func tile(at p: NSPoint) -> Tile? {
        tiles.first { abs(p.x - $0.centerX) <= (iconSize + gap) / 2 && p.y >= 0 && p.y <= pad + iconSize + 8 }
    }

    // MARK: 鼠标 → 冲量

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let now = CACurrentMediaTime()
        if let last = lastMouse, now - last.t > 0.001 {
            let vx = max(-4000, min(4000, (p.x - last.x) / CGFloat(now - last.t)))
            for t in tiles {
                let d = (p.x - t.centerX) / 55
                t.vs += vx * 0.0011 * exp(-d * d)
            }
        }
        lastMouse = (p.x, now)
        let h = tile(at: p)
        if h !== hovered {
            hovered = h
            h?.vq += 1.6                    // 进入时往上一弹
            showLabel(for: h)
        }
    }

    override func mouseExited(with e: NSEvent) {
        lastMouse = nil; hovered = nil; showLabel(for: nil)
    }

    override func mouseDown(with e: NSEvent) {
        pressed = tile(at: convert(e.locationInWindow, from: nil))
        pressed?.vq -= 3.5                  // 按下：压扁
    }

    override func mouseUp(with e: NSEvent) {
        guard let t = pressed else { return }
        pressed = nil
        t.vq += 5                           // 松开：弹起
        guard tile(at: convert(e.locationInWindow, from: nil)) === t else { return }
        NSWorkspace.shared.openApplication(at: t.url, configuration: .init())
    }

    override func rightMouseDown(with e: NSEvent) {
        let menu = NSMenu()
        if let t = tile(at: convert(e.locationInWindow, from: nil)), t.running,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.standardizedFileURL == t.url }) {
            let item = NSMenuItem(title: "退出 \(t.name)", action: #selector(quitApp(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = app
            menu.addItem(item); menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "退出 Jelly Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: e, for: self)
    }

    @objc func quitApp(_ sender: NSMenuItem) { (sender.representedObject as? NSRunningApplication)?.terminate() }

    func showLabel(for t: Tile?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let t {
            let text = t.name
            let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 16
            label.string = text
            label.frame = CGRect(x: t.centerX - w / 2, y: bounds.height - 22, width: w, height: 18)
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.isHidden = false
        } else { label.isHidden = true }
        CATransaction.commit()
    }

    func kickWave() {
        for (i, t) in tiles.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { t.vs += 2.2; t.vq += 1.2 }
        }
    }

    // MARK: 物理

    @objc func frame(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        var remaining = min(now - lastStep, 0.05)
        lastStep = now
        let h: CGFloat = 1.0 / 480
        while remaining > 0 {
            let dt = CGFloat(min(remaining, Double(h)))
            remaining -= Double(dt)
            clock += dt
            for (i, t) in tiles.enumerated() {
                let left = i > 0 ? tiles[i - 1].s : t.s
                let right = i < tiles.count - 1 ? tiles[i + 1].s : t.s
                t.vs += (-shearK * t.s - shearC * t.vs + coupling * (left + right - 2 * t.s)) * dt
                t.vq += (-squashK * t.q - squashC * t.vq) * dt
            }
            for t in tiles {
                t.s = max(-0.6, min(0.6, t.s + t.vs * dt))
                t.q = max(-0.4, min(0.6, t.q + t.vq * dt))
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let idle = jellyCurve(CGFloat(CACurrentMediaTime()))
        tiles.forEach { $0.render(extra: idle) }
        CATransaction.commit()
    }
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var bg: NSVisualEffectView!
    var icons: IconsView!
    var cache: [URL: Tile] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true

        let root = NSView()
        bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 20
        bg.layer?.masksToBounds = true
        icons = IconsView(frame: .zero)
        root.addSubview(bg)
        root.addSubview(icons)
        panel.contentView = root

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appsChanged(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appsChanged(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        reload()
        panel.orderFrontRegardless()
        icons.startLink()
        setupDesktop()

        // kill -USR1 <pid> 触发一次波浪，方便调试/截图
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.icons.kickWave() }
        src.resume()
        sigSource = src
    }
    var sigSource: DispatchSourceSignal?

    func pinnedURLs() -> [URL] {
        var urls = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        let items = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        for item in items {
            if let tile = item["tile-data"] as? [String: Any],
               let file = tile["file-data"] as? [String: Any],
               let s = file["_CFURLString"] as? String,
               let u = URL(string: s) ?? Optional(URL(fileURLWithPath: s)) {
                urls.append(u.standardizedFileURL)
            }
        }
        return urls
    }

    @objc func appsChanged(_ n: Notification) {
        let launched = n.name == NSWorkspace.didLaunchApplicationNotification
        let url = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleURL?.standardizedFileURL
        reload()
        if launched, let url, let t = cache[url] { t.vq += 6; t.vs += 1 }
    }

    @objc func reload() {
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleURL?.standardizedFileURL })
        var urls: [URL] = []
        for u in pinnedURLs() + running.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where !urls.contains(u) && FileManager.default.fileExists(atPath: u.path) {
            urls.append(u)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let tiles = urls.map { u -> Tile in
            let t = cache[u] ?? Tile(url: u, scale: scale)
            cache[u] = t
            t.running = running.contains(u)
            return t
        }

        let w = pad * 2 + CGFloat(tiles.count) * iconSize + CGFloat(max(tiles.count - 1, 0)) * gap
        let barH = iconSize + pad * 2
        let h = barH + headroom
        let screen = NSScreen.main!.visibleFrame
        panel.setFrame(NSRect(x: screen.midX - w / 2, y: screen.minY + 6, width: w, height: h), display: true)
        bg.frame = NSRect(x: 0, y: 0, width: w, height: barH)
        icons.frame = NSRect(x: 0, y: 0, width: w, height: h)
        icons.layout(tiles: tiles)
    }
}


// MARK: - 桌面图标层：自己画桌面图标，和 Dock 用同一个时钟同拍起伏
// 需要把 Finder 自带的桌面图标关掉，否则会重叠：
//   defaults write com.apple.finder CreateDesktop false && killall Finder

let deskIcon: CGFloat = 64, deskCellW: CGFloat = 96, deskCellH: CGFloat = 100, deskLabelH: CGFloat = 30

final class DesktopView: NSView {
    struct Item { let url: URL; let cell: CALayer; let icon: CALayer }
    var items: [Item] = []
    var selected: URL?
    var link: CADisplayLink?
    var watcher: DispatchSourceFileSystemObject?
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func start() {
        reload()
        link = displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in self?.reload() }
            src.setCancelHandler { close(fd) }
            src.resume()
            watcher = src
        }
    }

    func reload() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        items.forEach { $0.cell.removeFromSuperlayer() }
        items = []
        let urls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let scale = window?.backingScaleFactor ?? 2
        let rows = max(1, Int((bounds.height - 16) / deskCellH))
        for (i, u) in urls.enumerated() {
            let col = CGFloat(i / rows), row = CGFloat(i % rows)
            let cell = CALayer()
            cell.frame = CGRect(x: bounds.width - 16 - deskCellW * (col + 1),
                                y: bounds.height - 8 - deskCellH * (row + 1),
                                width: deskCellW, height: deskCellH)
            cell.cornerRadius = 8

            let img = NSWorkspace.shared.icon(forFile: u.path)
            img.size = NSSize(width: deskIcon, height: deskIcon)
            let icon = CALayer()
            icon.contents = img.layerContents(forContentsScale: scale)
            icon.contentsScale = scale
            icon.bounds = CGRect(x: 0, y: 0, width: deskIcon, height: deskIcon)
            icon.anchorPoint = CGPoint(x: 0.5, y: 0)                 // 底边贴地
            icon.position = CGPoint(x: deskCellW / 2, y: deskLabelH + 2)
            cell.addSublayer(icon)

            let label = CATextLayer()
            label.string = FileManager.default.displayName(atPath: u.path)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.fontSize = 12
            label.foregroundColor = NSColor.white.cgColor
            label.shadowColor = NSColor.black.cgColor
            label.shadowOpacity = 0.9
            label.shadowRadius = 2
            label.shadowOffset = CGSize(width: 0, height: -1)
            label.alignmentMode = .center
            label.isWrapped = true
            label.truncationMode = .middle
            label.contentsScale = scale
            label.frame = CGRect(x: 2, y: 0, width: deskCellW - 4, height: deskLabelH)
            cell.addSublayer(label)

            layer!.addSublayer(cell)
            items.append(Item(url: u, cell: cell, icon: icon))
        }
        updateSelection()
        CATransaction.commit()
    }

    func updateSelection() {
        for it in items {
            it.cell.backgroundColor = it.url == selected ? NSColor.white.withAlphaComponent(0.22).cgColor : nil
        }
    }

    @objc func tick(_ l: CADisplayLink) {
        let sy = 1 + jellyCurve(CGFloat(CACurrentMediaTime()))
        let t = CGAffineTransform(scaleX: 1 / sy, y: sy)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        items.forEach { $0.icon.setAffineTransform(t) }
        CATransaction.commit()
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let hit = items.first { $0.cell.frame.contains(p) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        selected = hit?.url
        updateSelection()
        CATransaction.commit()
        if e.clickCount == 2, let u = hit?.url { NSWorkspace.shared.open(u) }
    }
}

extension AppDelegate {
    func setupDesktop() {
        guard let screen = NSScreen.main else { return }
        let win = NSWindow(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let v = DesktopView(frame: NSRect(origin: .zero, size: screen.visibleFrame.size))
        win.contentView = v
        win.orderFrontRegardless()
        desktopWindow = win
        v.start()
    }
}
var desktopWindow: NSWindow?

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
