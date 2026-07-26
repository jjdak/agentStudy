# HTML 版本

这里是 `docs/` 三篇 Markdown 的静态 HTML 版本。

## 阅读

直接用浏览器打开 `index.html`，或通过任意静态文件服务器访问本目录。

公式使用固定版本的 MathJax，流程图使用固定版本的 Mermaid；首次打开时需要联网加载这两个浏览器脚本。正文、样式和图片均保存在仓库中，即使脚本加载失败也仍可阅读。

## 重新生成

Markdown 是唯一正文来源。修改 `docs/*.md` 后，在仓库根目录运行：

```bash
node html/build.mjs
```

构建脚本使用 Node.js 标准库，不需要安装 npm 依赖。它会重新生成：

- `html/index.html`
- `html/01_foundations.html`
- `html/02_coding_agent_playbook.html`
- `html/03_personal_practice.html`
- `html/assets/foundations/`

不要直接修改生成的正文页面；应先修改 Markdown，再重新运行构建脚本。
