# Jelly Dock

一个会 Q 弹的 macOS Dock 替代品：Dock 图标和桌面图标踩着同一个节拍一起上下起伏（体积守恒的挤压/拉伸，底边贴地），鼠标划过、点击时还有阻尼弹簧的果冻晃动。

灵感来自那种「车/玩偶像果冻一样弹」的视频。

## 运行

需要 macOS 14+ 和 Xcode Command Line Tools。

```sh
./build.sh
./jelly-dock &
```

右键 Dock 空白处 →「退出 Jelly Dock」。

## 配合系统设置

系统 Dock 和 Finder 桌面图标无法被改造（要关 SIP 注入，本项目不这么做），所以 Jelly Dock 是自己重新画一份。建议把原版藏起来：

```sh
# 系统 Dock 自动隐藏且几乎不弹出
defaults write com.apple.dock autohide -bool true && defaults write com.apple.dock autohide-delay -float 1000 && killall Dock
# 关掉 Finder 桌面图标（由 Jelly Dock 绘制）
defaults write com.apple.finder CreateDesktop false && killall Finder
```

恢复：

```sh
defaults delete com.apple.dock autohide-delay && killall Dock
defaults delete com.apple.finder CreateDesktop && killall Finder
```

注意：关掉 Finder 桌面图标后，退出 Jelly Dock 桌面就是空的（文件仍在 `~/Desktop`）。

## 功能

- Dock：读取系统 Dock 的固定 App + 正在运行的 App，运行指示点，悬停显示名称，点击打开，右键退出 App
- 桌面：显示 `~/Desktop` 内容（按名称排序，自动刷新），单击选中、双击打开
- `kill -USR1 <pid>` 触发一次横向波浪（调试用）

暂不支持：拖动、文件夹/下载栈/废纸篓、桌面图标位置记忆、多显示器。

## 浏览器：油猴脚本

[`userscript/jelly-page.user.js`](userscript/jelly-page.user.js) 让网页里的文字和图标用同一个节拍一起弹。装好 Tampermonkey / Violentmonkey 后打开 [raw 链接](https://raw.githubusercontent.com/Chr0mium24/jelly-dock/main/userscript/jelly-page.user.js) 即可安装。

- 逐字模式（默认）：中日韩字 / emoji 一个一块、英文一个单词一块。原文本节点保留在原位只清空内容，Vue/React/Lit 更新时会自动重拆，不会把组件弄丢；支持 open Shadow DOM（如 B 站评论区）和动态内容（弹幕）
- 整块模式：整段文字一起弹，不改 DOM
- `Alt+J` 或脚本菜单：在当前站点开/关；只对视口附近的元素挂动画，所有元素同一相位

## 调参

`main.swift` 顶部：

| 参数 | 作用 |
|---|---|
| `beatHz` | 起伏频率（次/秒） |
| `beatAmp` | 起伏幅度（0.12 = 12%） |
| `shearK` / `shearC` / `coupling` | 鼠标划过时的摆动刚度、阻尼、相邻耦合 |
| `squashK` / `squashC` | 点击/悬停时挤压弹簧的刚度、阻尼 |
