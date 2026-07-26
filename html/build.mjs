import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const docsDir = join(repoRoot, "docs");
const assetsDir = join(scriptDir, "assets");
const repoUrl = "https://github.com/jjdak/agentStudy";
const assetVersion = "20260726-10";

const pages = [
  {
    source: "01_foundations.md",
    output: "01_foundations.html",
    slides: "01_foundations_slides.html",
    eyebrow: "原理",
    description: "从 Token、Transformer 和幻觉机制，走到工具、权限与验证器。",
  },
  {
    source: "02_coding_agent_playbook.md",
    output: "02_coding_agent_playbook.html",
    eyebrow: "方法",
    description: "把 Coding Agent 作为可观察、可纠偏、可验收的工程系统使用。",
  },
  {
    source: "03_personal_practice.md",
    output: "03_personal_practice.html",
    eyebrow: "实践",
    description: "使用检查清单、提示词模板和标准任务完成个人练习。",
  },
];

mkdirSync(assetsDir, { recursive: true });
cpSync(join(docsDir, "assets", "foundations"), join(assetsDir, "foundations"), {
  recursive: true,
  force: true,
});

const pageBySource = new Map(pages.map((page) => [page.source, page.output]));
const pageTitles = new Map();
const renderedPages = new Map();

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function slugify(value, usedIds) {
  const base =
    value
      .toLowerCase()
      .replace(/[`*_~]/g, "")
      .replace(/[^\p{Letter}\p{Number}\s-]/gu, "")
      .trim()
      .replace(/\s+/g, "-") || "section";
  const count = usedIds.get(base) ?? 0;
  usedIds.set(base, count + 1);
  return count === 0 ? base : `${base}-${count + 1}`;
}

function rewriteHref(href, sourceName) {
  if (/^(?:https?:|mailto:|#)/i.test(href)) return href;

  const [pathPart, fragment = ""] = href.split("#", 2);
  if (pageBySource.has(pathPart)) {
    return `${pageBySource.get(pathPart)}${fragment ? `#${fragment}` : ""}`;
  }

  if (pathPart.endsWith(".md")) {
    const absoluteTarget = resolve(docsDir, dirname(sourceName), pathPart);
    const repoPath = relative(repoRoot, absoluteTarget).replaceAll("\\", "/");
    return `${repoUrl}/blob/main/${repoPath}${fragment ? `#${fragment}` : ""}`;
  }

  return href;
}

function inlineMarkdown(source, sourceName) {
  const placeholders = [];
  const hold = (html) => {
    const token = `\u0000${placeholders.length}\u0000`;
    placeholders.push(html);
    return token;
  };

  let value = source;

  value = value.replace(/`([^`\n]+)`/g, (_, code) =>
    hold(`<code>${escapeHtml(code)}</code>`),
  );

  value = value.replace(
    /\[!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
    (_, alt, src, href) =>
      hold(
        `<a class="image-link" href="${escapeHtml(rewriteHref(href, sourceName))}" target="_blank" rel="noreferrer"><img src="${escapeHtml(src)}" alt="${escapeHtml(alt)}" loading="lazy"></a>`,
      ),
  );

  value = value.replace(
    /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
    (_, alt, src) =>
      hold(
        `<img src="${escapeHtml(src)}" alt="${escapeHtml(alt)}" loading="lazy">`,
      ),
  );

  value = value.replace(
    /\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
    (_, label, href) => {
      const rewritten = rewriteHref(href, sourceName);
      const external = /^https?:/i.test(rewritten);
      return hold(
        `<a href="${escapeHtml(rewritten)}"${external ? ' target="_blank" rel="noreferrer"' : ""}>${escapeHtml(label)}</a>`,
      );
    },
  );

  value = escapeHtml(value);
  value = value.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  value = value.replace(/~~([^~]+)~~/g, "<del>$1</del>");
  value = value.replace(/(^|[\s（(])\*([^*\n]+)\*(?=$|[\s，。；：、）)])/g, "$1<em>$2</em>");

  let restored = value;
  for (let pass = 0; pass <= placeholders.length; pass += 1) {
    if (!restored.includes("\u0000")) break;
    restored = restored.replace(
      /\u0000(\d+)\u0000/g,
      (_, index) => placeholders[Number(index)],
    );
  }
  return restored;
}

function splitTableRow(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function isTableDivider(line) {
  const cells = splitTableRow(line);
  return cells.length > 0 && cells.every((cell) => /^:?-{3,}:?$/.test(cell));
}

function renderMarkdown(markdown, sourceName) {
  const lines = markdown.replaceAll("\r\n", "\n").split("\n");
  const html = [];
  const toc = [];
  const usedIds = new Map();
  let paragraph = [];
  let listType = null;
  let blockquote = [];
  let inFence = false;
  let fenceLanguage = "";
  let fenceLines = [];

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    html.push(`<p>${inlineMarkdown(paragraph.join(" "), sourceName)}</p>`);
    paragraph = [];
  };

  const flushList = () => {
    if (!listType) return;
    html.push(`</${listType}>`);
    listType = null;
  };

  const flushBlockquote = () => {
    if (blockquote.length === 0) return;
    html.push(
      `<blockquote><p>${inlineMarkdown(blockquote.join(" "), sourceName)}</p></blockquote>`,
    );
    blockquote = [];
  };

  const flushOpenBlocks = () => {
    flushParagraph();
    flushList();
    flushBlockquote();
  };

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];

    if (inFence) {
      if (/^```/.test(line)) {
        const code = fenceLines.join("\n");
        if (fenceLanguage === "math") {
          html.push(`<div class="math-block">\\[\n${escapeHtml(code)}\n\\]</div>`);
        } else if (fenceLanguage === "mermaid") {
          html.push(`<pre class="mermaid">${escapeHtml(code)}</pre>`);
        } else {
          const languageClass = fenceLanguage
            ? ` class="language-${escapeHtml(fenceLanguage)}"`
            : "";
          html.push(
            `<div class="code-block"><button class="copy-code" type="button">复制</button><pre><code${languageClass}>${escapeHtml(code)}</code></pre></div>`,
          );
        }
        inFence = false;
        fenceLanguage = "";
        fenceLines = [];
      } else {
        fenceLines.push(line);
      }
      continue;
    }

    const fenceMatch = line.match(/^```([\w+-]*)\s*$/);
    if (fenceMatch) {
      flushOpenBlocks();
      inFence = true;
      fenceLanguage = fenceMatch[1].toLowerCase();
      continue;
    }

    if (/^\s*$/.test(line)) {
      flushOpenBlocks();
      continue;
    }

    if (/^\s*<!--.*-->\s*$/.test(line)) {
      continue;
    }

    const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);
    if (headingMatch) {
      flushOpenBlocks();
      const level = headingMatch[1].length;
      const label = headingMatch[2].trim();
      const id = slugify(label, usedIds);
      const renderedLabel = inlineMarkdown(label, sourceName);
      html.push(
        `<h${level} id="${escapeHtml(id)}">${renderedLabel}<a class="heading-anchor" href="#${escapeHtml(id)}" aria-label="链接到本节">#</a></h${level}>`,
      );
      if (level >= 2 && level <= 3) {
        toc.push({ level, label: label.replace(/[`*_]/g, ""), id });
      }
      continue;
    }

    if (line.startsWith("> ")) {
      flushParagraph();
      flushList();
      blockquote.push(line.slice(2).trim());
      continue;
    }

    if (
      line.includes("|") &&
      index + 1 < lines.length &&
      isTableDivider(lines[index + 1])
    ) {
      flushOpenBlocks();
      const headers = splitTableRow(line);
      index += 2;
      const rows = [];
      while (index < lines.length && lines[index].trim().startsWith("|")) {
        rows.push(splitTableRow(lines[index]));
        index += 1;
      }
      index -= 1;
      html.push('<div class="table-wrap"><table><thead><tr>');
      for (const header of headers) {
        html.push(`<th>${inlineMarkdown(header, sourceName)}</th>`);
      }
      html.push("</tr></thead><tbody>");
      for (const row of rows) {
        html.push("<tr>");
        for (const cell of row) {
          html.push(`<td>${inlineMarkdown(cell, sourceName)}</td>`);
        }
        html.push("</tr>");
      }
      html.push("</tbody></table></div>");
      continue;
    }

    const unorderedMatch = line.match(/^[-*+]\s+(.+)$/);
    const orderedMatch = line.match(/^(\d+)\.\s+(.+)$/);
    if (unorderedMatch || orderedMatch) {
      flushParagraph();
      flushBlockquote();
      const requestedType = orderedMatch ? "ol" : "ul";
      if (listType !== requestedType) {
        flushList();
        const start =
          orderedMatch && orderedMatch[1] !== "1"
            ? ` start="${orderedMatch[1]}"`
            : "";
        html.push(`<${requestedType}${start}>`);
        listType = requestedType;
      }
      let item = orderedMatch ? orderedMatch[2] : unorderedMatch[1];
      const taskMatch = item.match(/^\[([ xX])\]\s+(.+)$/);
      if (taskMatch) {
        const checked = taskMatch[1].toLowerCase() === "x";
        item = `<input type="checkbox" disabled${checked ? " checked" : ""}> ${inlineMarkdown(taskMatch[2], sourceName)}`;
        html.push(`<li class="task-item">${item}</li>`);
      } else {
        html.push(`<li>${inlineMarkdown(item, sourceName)}</li>`);
      }
      continue;
    }

    flushList();
    flushBlockquote();
    paragraph.push(line.trim());
  }

  if (inFence) {
    throw new Error(`Unclosed code fence in ${sourceName}`);
  }

  flushOpenBlocks();
  return { html: html.join("\n"), toc };
}

function pageNavigation(activeOutput) {
  return pages
    .map((page, index) => {
      const active = page.output === activeOutput ? " is-active" : "";
      return `<a class="chapter-link${active}" href="${page.output}">
        <span class="chapter-number">0${index + 1}</span>
        <span>${escapeHtml(pageTitles.get(page.source))}</span>
      </a>`;
    })
    .join("\n");
}

function tocNavigation(toc) {
  return toc
    .map(
      (item) =>
        `<a class="toc-link toc-level-${item.level}" href="#${escapeHtml(item.id)}">${escapeHtml(item.label)}</a>`,
    )
    .join("\n");
}

function documentShell({ title, body, toc, activeOutput, description }) {
  const currentPage = pages.find((page) => page.output === activeOutput);
  const presentationLink = currentPage?.slides
    ? `        <a class="presentation-entry" href="${currentPage.slides}">演示模式 →</a>
`
    : "";
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escapeHtml(description)}">
  <title>${escapeHtml(title)} · Agent Study</title>
  <link rel="stylesheet" href="assets/style.css?v=${assetVersion}">
  <script>
    window.MathJax = {
      tex: { inlineMath: [["\\\\(", "\\\\)"]], displayMath: [["\\\\[", "\\\\]"]] },
      options: { skipHtmlTags: ["script", "noscript", "style", "textarea", "pre", "code"] }
    };
  </script>
  <script defer src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
  <script defer src="assets/app.js?v=${assetVersion}"></script>
</head>
<body data-page="${escapeHtml(activeOutput)}">
  <div class="reading-progress" aria-hidden="true"><span></span></div>
  <header class="mobile-header">
    <a class="brand compact" href="index.html">Agent Study</a>
    <div class="mobile-actions">
      <button class="icon-button theme-toggle" type="button" aria-label="切换颜色主题">◐</button>
      <button class="icon-button nav-toggle" type="button" aria-label="打开目录">☰</button>
    </div>
  </header>
  <div class="site-layout">
    <aside class="sidebar">
      <a class="brand" href="index.html">
        <span class="brand-mark">A</span>
        <span><strong>Agent Study</strong><small>个人学习手册</small></span>
      </a>
      <nav class="chapter-nav" aria-label="章节">
        ${pageNavigation(activeOutput)}
      </nav>
      <div class="sidebar-footer">
${presentationLink}\
        <button class="theme-button theme-toggle" type="button">切换深浅主题</button>
        <a href="${repoUrl}" target="_blank" rel="noreferrer">查看 GitHub 源码 ↗</a>
      </div>
    </aside>
    <main class="document-main">
      <article class="document">
        ${body}
        <nav class="page-switcher" aria-label="相邻章节">
          ${adjacentPageLinks(activeOutput)}
        </nav>
      </article>
    </main>
    <aside class="page-toc" aria-label="本页目录">
      <div class="toc-title">本页目录</div>
      ${tocNavigation(toc)}
      <a class="back-to-top" href="#">返回顶部 ↑</a>
    </aside>
  </div>
</body>
</html>`;
}

function splitPresentationSlides(markdown, sourceName) {
  const marker = /^\s*<!--\s*slide(?:\s*:\s*(.*?))?\s*-->\s*$/;
  const slides = [];
  let current = { title: "", lines: [] };

  const pushCurrent = () => {
    const content = current.lines.join("\n").trim();
    if (!content) return;
    const withTitle = current.title
      ? `## ${current.title}\n\n${content}`
      : content;
    const rendered = renderMarkdown(withTitle, sourceName).html;
    const hasImage = rendered.includes("<img ");
    const hasMermaid = rendered.includes('class="mermaid"');
    const nonVisualText = current.lines
      .map((line) => line.trim())
      .filter(
        (line) =>
          line &&
          !/^#{1,6}\s/.test(line) &&
          !line.includes("![") &&
          !/^\*图：/.test(line),
      )
      .join(" ");
    const layoutClass = hasImage
      ? nonVisualText
        ? "layout-split"
        : "layout-image"
      : hasMermaid
        ? "layout-visual"
        : "layout-text";
    slides.push({
      html: rendered,
      title:
        current.title ||
        content.match(/^#{1,6}\s+(.+)$/m)?.[1]?.replace(/[`*_]/g, "") ||
        `第 ${slides.length + 1} 页`,
      classes: [
        layoutClass,
        slides.length === 0 ? "is-cover" : "",
        hasImage ? "has-image" : "",
        rendered.includes("<table>") ? "has-table" : "",
        hasMermaid ? "has-mermaid" : "",
        rendered.includes('class="math-block"') ? "has-math" : "",
        rendered.includes('class="code-block"') ? "has-code" : "",
      ]
        .filter(Boolean)
        .join(" "),
    });
  };

  for (const line of markdown.replaceAll("\r\n", "\n").split("\n")) {
    const match = line.match(marker);
    if (match) {
      pushCurrent();
      current = { title: match[1]?.trim() ?? "", lines: [] };
      continue;
    }
    current.lines.push(line);
  }
  pushCurrent();

  if (slides.length < 2) {
    throw new Error(
      `${sourceName} needs standalone <!-- slide --> markers for presentation mode`,
    );
  }
  return slides;
}

function presentationShell({ title, sourcePage, slides }) {
  const slideSections = slides
    .map(
      (slide, index) => `<section class="slide ${slide.classes}" id="slide-${index + 1}" data-slide-index="${index}" aria-label="第 ${index + 1} 页：${escapeHtml(slide.title)}">
        <div class="slide-content">
          ${slide.html}
        </div>
      </section>`,
    )
    .join("\n");

  const overviewItems = slides
    .map(
      (slide, index) => `<button class="overview-item" type="button" data-target-slide="${index}">
        <span>${String(index + 1).padStart(2, "0")}</span>
        <strong>${escapeHtml(slide.title)}</strong>
      </button>`,
    )
    .join("\n");

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escapeHtml(title)}的演示模式。">
  <title>${escapeHtml(title)} · 演示模式</title>
  <link rel="stylesheet" href="assets/style.css?v=${assetVersion}">
  <link rel="stylesheet" href="assets/slides.css?v=${assetVersion}">
  <script>
    window.MathJax = {
      tex: { inlineMath: [["\\\\(", "\\\\)"]], displayMath: [["\\\\[", "\\\\]"]] },
      options: { skipHtmlTags: ["script", "noscript", "style", "textarea", "pre", "code"] }
    };
  </script>
  <script defer src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
  <script defer src="assets/slides.js?v=${assetVersion}"></script>
</head>
<body class="slides-page">
  <header class="deck-header">
    <a class="deck-brand" href="index.html">Agent Study</a>
    <div class="deck-mode">演示模式</div>
    <div class="deck-header-actions">
      <a href="${sourcePage}">阅读全文</a>
      <button class="deck-icon theme-toggle" type="button" aria-label="切换颜色主题">◐</button>
      <button class="deck-icon overview-toggle" type="button" aria-label="打开页面总览">▦</button>
      <button class="deck-icon fullscreen-toggle" type="button" aria-label="进入全屏">⛶</button>
    </div>
  </header>
  <main class="deck" aria-live="polite">
    ${slideSections}
  </main>
  <div class="deck-progress" aria-hidden="true"><span></span></div>
  <footer class="deck-footer">
    <button class="deck-nav previous-slide" type="button" aria-label="上一页">←</button>
    <div class="slide-counter"><strong>01</strong><span>/ ${String(slides.length).padStart(2, "0")}</span></div>
    <p class="deck-hint">方向键切换 · O 总览 · F 全屏</p>
    <button class="deck-nav next-slide" type="button" aria-label="下一页">→</button>
  </footer>
  <div class="overview-panel" aria-hidden="true">
    <div class="overview-header">
      <strong>页面总览</strong>
      <button class="overview-close" type="button" aria-label="关闭页面总览">关闭</button>
    </div>
    <div class="overview-grid">
      ${overviewItems}
    </div>
  </div>
  <div class="image-viewer" role="dialog" aria-modal="true" aria-hidden="true" aria-label="图片查看器">
    <div class="image-viewer-toolbar">
      <strong class="image-viewer-title">图片</strong>
      <div class="image-viewer-actions">
        <a class="image-viewer-source" href="#" target="_blank" rel="noreferrer" hidden>查看来源 ↗</a>
        <button type="button" data-viewer-action="zoom-out" aria-label="缩小图片">−</button>
        <span class="image-viewer-scale">100%</span>
        <button type="button" data-viewer-action="zoom-in" aria-label="放大图片">＋</button>
        <button type="button" data-viewer-action="reset" aria-label="重置图片缩放">重置</button>
        <button type="button" data-viewer-action="close" aria-label="关闭图片查看器">关闭</button>
      </div>
    </div>
    <div class="image-viewer-stage">
      <img class="image-viewer-image" alt="" draggable="false">
    </div>
    <p class="image-viewer-help">滚轮或 ＋/− 缩放 · 放大后拖动 · 双击切换 · Esc 返回</p>
  </div>
</body>
</html>`;
}

function adjacentPageLinks(activeOutput) {
  const currentIndex = pages.findIndex((page) => page.output === activeOutput);
  const previous = pages[currentIndex - 1];
  const next = pages[currentIndex + 1];
  return [
    previous
      ? `<a class="previous" href="${previous.output}"><span>上一篇</span>${escapeHtml(pageTitles.get(previous.source))}</a>`
      : "<span></span>",
    next
      ? `<a class="next" href="${next.output}"><span>下一篇</span>${escapeHtml(pageTitles.get(next.source))}</a>`
      : '<a class="next" href="index.html"><span>完成</span>返回学习首页</a>',
  ].join("\n");
}

for (const page of pages) {
  const markdown = readFileSync(join(docsDir, page.source), "utf8");
  const titleMatch = markdown.match(/^#\s+(.+)$/m);
  if (!titleMatch) throw new Error(`Missing H1 in ${page.source}`);
  pageTitles.set(page.source, titleMatch[1].trim());
  renderedPages.set(page.source, renderMarkdown(markdown, page.source));
}

for (const page of pages) {
  const rendered = renderedPages.get(page.source);
  const title = pageTitles.get(page.source);
  writeFileSync(
    join(scriptDir, page.output),
    documentShell({
      title,
      body: rendered.html,
      toc: rendered.toc,
      activeOutput: page.output,
      description: page.description,
    }),
  );
}

for (const page of pages.filter((item) => item.slides)) {
  const markdown = readFileSync(join(docsDir, page.source), "utf8");
  const slides = splitPresentationSlides(markdown, page.source);
  writeFileSync(
    join(scriptDir, page.slides),
    presentationShell({
      title: pageTitles.get(page.source),
      sourcePage: page.output,
      slides,
    }),
  );
}

const totalMinutes = "约 4–6 小时阅读，另加实践时间";
const cards = pages
  .map(
    (page, index) => `<a class="home-card" href="${page.output}">
      <span class="card-index">0${index + 1}</span>
      <span class="card-eyebrow">${escapeHtml(page.eyebrow)}</span>
      <h2>${escapeHtml(pageTitles.get(page.source).replace(/^0\d\.\s*/, ""))}</h2>
      <p>${escapeHtml(page.description)}</p>
      <span class="card-action">开始阅读 →</span>
    </a>`,
  )
  .join("\n");

const indexHtml = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="从 LLM 原理到 Coding Agent 实践的个人学习手册。">
  <title>Agent Study · 个人学习手册</title>
  <link rel="stylesheet" href="assets/style.css?v=${assetVersion}">
  <script defer src="assets/app.js?v=${assetVersion}"></script>
</head>
<body class="home-page">
  <header class="home-header">
    <a class="brand compact" href="index.html">Agent Study</a>
    <div>
      <button class="theme-button theme-toggle" type="button">切换深浅主题</button>
      <a class="github-link" href="${repoUrl}" target="_blank" rel="noreferrer">GitHub ↗</a>
    </div>
  </header>
  <main class="home-main">
    <section class="hero">
      <p class="hero-kicker">PERSONAL LEARNING PATH · 2026</p>
      <h1>从理解模型，<br>到可靠地使用 Coding Agent</h1>
      <p class="hero-lead">一套面向软件工程师的个人学习材料。先理解生成与幻觉，再学习任务设计、工具反馈、权限控制和独立验收，最后在可重复环境中练习。</p>
      <div class="hero-actions">
        <a class="primary-button" href="${pages[0].output}">从第一篇开始</a>
        <a class="secondary-button" href="${pages[0].slides}">打开演示模式</a>
        <span>${totalMinutes}</span>
      </div>
    </section>
    <section class="learning-path" aria-label="学习路径">
      ${cards}
    </section>
    <section class="principle-strip">
      <p>贯穿原则</p>
      <strong>模型负责提出候选方案，工具提供观察，验证器决定能否接受。</strong>
    </section>
  </main>
  <footer class="home-footer">
    <span>内容以仓库中的 Markdown 为唯一来源。</span>
    <span>运行 <code>node html/build.mjs</code> 重新生成。</span>
  </footer>
</body>
</html>`;

writeFileSync(join(scriptDir, "index.html"), indexHtml);

for (const file of ["style.css", "app.js", "slides.css", "slides.js"]) {
  if (!existsSync(join(assetsDir, file))) {
    throw new Error(`Missing required asset: html/assets/${file}`);
  }
}

const generatedPageCount =
  pages.length + pages.filter((page) => page.slides).length + 1;
console.log(
  `Generated ${generatedPageCount} HTML pages in ${relative(repoRoot, scriptDir)}/`,
);
