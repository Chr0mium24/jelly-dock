// ==UserScript==
// @name         Jelly Page
// @namespace    https://github.com/Chr0mium24/jelly-dock
// @version      0.1.0
// @description  让网页里的字和图标像果冻一样同步上下弹（和 Jelly Dock 同一个节拍）
// @match        *://*/*
// @run-at       document-idle
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// ==/UserScript==

(() => {
  'use strict';

  // ---- 参数（与 Jelly Dock 一致：2.2 次/秒，12% 形变，只挤压/拉伸不倾斜）----
  const HZ = 2.2;
  const AMP = 0.12;
  const STEPS = 24;            // 正弦曲线采样点
  const MAX_WORDS = 30000;     // 逐字模式最多拆多少个 span
  const MAX_ICON = 320;        // 超过这个尺寸的图片不弹（横幅、视频封面）

  const cfg = Object.assign({ mode: 'char', off: {} }, GM_getValue('cfg', {}));
  const host = location.hostname;
  const save = () => GM_setValue('cfg', cfg);

  GM_registerMenuCommand(cfg.off[host] ? `在 ${host} 开启` : `在 ${host} 关闭`, toggleHost);
  GM_registerMenuCommand(`模式：${cfg.mode === 'char' ? '逐字（切到整块）' : '整块（切到逐字）'}`, () => {
    cfg.mode = cfg.mode === 'char' ? 'block' : 'char';
    save(); location.reload();
  });
  addEventListener('keydown', e => {
    if (e.altKey && e.code === 'KeyJ') { e.preventDefault(); toggleHost(); }
  }, true);

  function toggleHost() {
    if (cfg.off[host]) delete cfg.off[host]; else cfg.off[host] = true;
    save(); location.reload();
  }

  if (cfg.off[host]) return;

  // ---- 体积守恒的正弦挤压：scaleX = 1/(1+q), scaleY = 1+q ----
  const frames = Array.from({ length: STEPS + 1 }, (_, i) => {
    const q = AMP * Math.sin((2 * Math.PI * i) / STEPS);
    return { transform: `scale(${(1 / (1 + q)).toFixed(4)}, ${(1 + q).toFixed(4)})` };
  });
  const timing = { duration: 1000 / HZ, iterations: Infinity, composite: 'add' };

  const style = document.createElement('style');
  style.textContent = `
    .jl-w { display: inline-block; white-space: pre; }
    .jl-t { transform-origin: 50% 100% !important; }
  `;
  document.documentElement.appendChild(style);

  // ---- 只给视口附近的元素挂动画；startTime=0 让所有元素踩同一个相位 ----
  const anims = new Map();
  const io = new IntersectionObserver(entries => {
    for (const { target, isIntersecting } of entries) {
      if (isIntersecting && !anims.has(target)) {
        const a = target.animate(frames, timing);
        a.startTime = 0;
        anims.set(target, a);
      } else if (!isIntersecting && anims.has(target)) {
        anims.get(target).cancel();
        anims.delete(target);
      }
    }
  }, { rootMargin: '200px' });

  function mark(el) {
    if (el.classList.contains('jl-t')) return;
    if (el.parentElement && el.parentElement.closest('.jl-t')) return;  // 祖先已经在弹
    el.classList.add('jl-t');
    io.observe(el);
  }

  // ---- 图标 ----
  const ICON_SEL = 'img, svg, [role="img"], [class*="icon" i], [class*="emoji" i]';
  function scanIcons(root) {
    const list = root.matches && root.matches(ICON_SEL) ? [root] : [];
    if (root.querySelectorAll) list.push(...root.querySelectorAll(ICON_SEL));
    for (const el of list) {
      if (el.closest('svg') !== el && el.closest('svg')) continue;   // svg 内部子元素
      const r = el.getBoundingClientRect();
      if (r.width > MAX_ICON || r.height > MAX_ICON) continue;
      if (getComputedStyle(el).display === 'inline' && el.tagName !== 'IMG' && el.tagName !== 'svg') {
        el.style.display = 'inline-block';                           // 行内元素 transform 不生效
      }
      mark(el);
    }
  }

  // ---- 文字 ----
  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'INPUT', 'SELECT', 'OPTION', 'TITLE', 'svg']);
  // CJK 一个字一个块；拉丁文按单词；空白保留为文本以便正常换行
  const TOKEN = /[⺀-鿿가-힯豈-﫿＀-￯]|[^\s⺀-鿿가-힯豈-﫿＀-￯]+|\s+/g;
  let words = 0;

  function textNodes(root) {
    const out = [];
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(n) {
        const p = n.parentElement;
        if (!p || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        if (SKIP.has(p.tagName) || p.closest('svg, [contenteditable=""], [contenteditable="true"], .jl-w')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    for (let n; (n = w.nextNode());) out.push(n);
    return out;
  }

  function splitText(node) {
    if (words >= MAX_WORDS || node.parentElement.closest('.jl-t')) return;
    const frag = document.createDocumentFragment();
    for (const tok of node.nodeValue.match(TOKEN) || []) {
      if (/^\s+$/.test(tok)) { frag.appendChild(document.createTextNode(tok)); continue; }
      const s = document.createElement('span');
      s.className = 'jl-w';
      s.textContent = tok;
      frag.appendChild(s);
      words++;
    }
    const spans = [...frag.querySelectorAll('.jl-w')];
    node.replaceWith(frag);
    spans.forEach(mark);
  }

  const blockOf = el => {
    for (let e = el; e && e !== document.body; e = e.parentElement) {
      const d = getComputedStyle(e).display;
      if (d !== 'inline' && d !== 'contents') return e;
    }
    return null;
  };

  function scanText(root) {
    for (const n of textNodes(root)) {
      if (cfg.mode === 'char') splitText(n);
      else { const b = blockOf(n.parentElement); if (b) mark(b); }
    }
  }

  // ---- 扫描：首屏 + 之后动态插入的内容（空闲时分批处理）----
  const queue = [];
  let scheduled = false;
  const idle = window.requestIdleCallback || (fn => setTimeout(() => fn({ timeRemaining: () => 8 }), 50));

  function enqueue(node) {
    queue.push(node);
    if (!scheduled) { scheduled = true; idle(drain); }
  }
  function drain(deadline) {
    while (queue.length && deadline.timeRemaining() > 2) {
      const n = queue.shift();
      if (!n.isConnected) continue;
      scanIcons(n);
      scanText(n);
    }
    if (queue.length) idle(drain); else scheduled = false;
  }

  new MutationObserver(muts => {
    for (const m of muts) for (const n of m.addedNodes) {
      if (n.nodeType === 1 && !n.classList.contains('jl-w')) enqueue(n);
      else if (n.nodeType === 3 && n.parentElement) enqueue(n.parentElement);
    }
  }).observe(document.body, { childList: true, subtree: true });

  enqueue(document.body);
})();
