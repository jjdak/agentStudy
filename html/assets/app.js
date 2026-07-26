(() => {
  const root = document.documentElement;
  const storedTheme = localStorage.getItem("agent-study-theme");
  const preferredDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  root.dataset.theme = storedTheme || (preferredDark ? "dark" : "light");

  for (const button of document.querySelectorAll(".theme-toggle")) {
    button.addEventListener("click", () => {
      const next = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      localStorage.setItem("agent-study-theme", next);
      if (window.mermaid) {
        window.location.reload();
      }
    });
  }

  document.querySelector(".nav-toggle")?.addEventListener("click", () => {
    document.body.classList.toggle("nav-open");
  });

  for (const link of document.querySelectorAll(".chapter-link")) {
    link.addEventListener("click", () => document.body.classList.remove("nav-open"));
  }

  for (const button of document.querySelectorAll(".copy-code")) {
    button.addEventListener("click", async () => {
      const code = button.parentElement?.querySelector("code")?.textContent ?? "";
      try {
        await navigator.clipboard.writeText(code);
        button.textContent = "已复制";
        window.setTimeout(() => {
          button.textContent = "复制";
        }, 1400);
      } catch {
        button.textContent = "复制失败";
      }
    });
  }

  const progress = document.querySelector(".reading-progress span");
  const updateProgress = () => {
    if (!progress) return;
    const available = document.documentElement.scrollHeight - window.innerHeight;
    const ratio = available > 0 ? window.scrollY / available : 0;
    progress.style.width = `${Math.min(100, Math.max(0, ratio * 100))}%`;
  };
  window.addEventListener("scroll", updateProgress, { passive: true });
  updateProgress();

  const tocLinks = [...document.querySelectorAll(".toc-link")];
  const observedHeadings = tocLinks
    .map((link) => {
      const href = link.getAttribute("href");
      return href?.startsWith("#") ? document.getElementById(href.slice(1)) : null;
    })
    .filter(Boolean);
  if (tocLinks.length > 0 && observedHeadings.length > 0) {
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (!visible) return;
        for (const link of tocLinks) {
          link.classList.toggle(
            "is-current",
            link.getAttribute("href") === `#${visible.target.id}`,
          );
        }
      },
      { rootMargin: "-12% 0px -78% 0px" },
    );
    observedHeadings.forEach((heading) => observer.observe(heading));
  }

  window.addEventListener("load", () => {
    if (!window.mermaid) return;
    window.mermaid.initialize({
      startOnLoad: false,
      theme: root.dataset.theme === "dark" ? "dark" : "neutral",
      securityLevel: "strict",
      fontFamily: getComputedStyle(root).fontFamily,
    });
    window.mermaid.run({ querySelector: ".mermaid" }).catch((error) => {
      console.warn("Mermaid rendering failed", error);
    });
  });
})();
