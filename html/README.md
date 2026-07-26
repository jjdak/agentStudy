# HTML 版本

这里是 `docs/` 三篇 Markdown 的静态 HTML 版本。`01` 同时提供适合连续阅读的长文页和适合分享讲解的分页演示页。

## 阅读

直接用浏览器打开 `index.html`，或通过任意静态文件服务器访问本目录。

公式使用固定版本的 MathJax，流程图使用固定版本的 Mermaid；首次打开时需要联网加载这两个浏览器脚本。正文、样式和图片均保存在仓库中，即使脚本加载失败也仍可阅读。

演示模式入口为 `01_foundations_slides.html`。它支持：

- 方向键、Page Up/Page Down 或空格翻页；
- 触摸滑动、底部按钮和页码导航；
- 按 `O` 打开总览，按 `F` 切换全屏；
- 图片页自动使用图片主导或左右分栏布局；点击图片可全屏查看、缩放和拖动；
- 深浅主题以及浏览器打印/PDF 导出。

演示页和长文页复用 `docs/01_foundations.md`。源文件中的独立 `<!-- slide -->` 注释表示换页，`<!-- slide: 标题 -->` 会换页并为下一页补充演示标题；这些注释不会显示在 GitHub 或长文页中。

## 重新生成

Markdown 是唯一正文来源。修改 `docs/*.md` 后，在仓库根目录运行：

```bash
node html/build.mjs
```

构建脚本使用 Node.js 标准库，不需要安装 npm 依赖。它会重新生成：

- `html/index.html`
- `html/01_foundations.html`
- `html/01_foundations_slides.html`
- `html/02_coding_agent_playbook.html`
- `html/03_personal_practice.html`
- `html/assets/foundations/`

不要直接修改生成的正文页面；应先修改 Markdown，再重新运行构建脚本。
