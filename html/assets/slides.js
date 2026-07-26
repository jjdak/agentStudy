(() => {
  const root = document.documentElement;
  const slides = [...document.querySelectorAll(".slide")];
  const overviewItems = [...document.querySelectorAll(".overview-item")];
  const counter = document.querySelector(".slide-counter strong");
  const progress = document.querySelector(".deck-progress span");
  const previousButton = document.querySelector(".previous-slide");
  const nextButton = document.querySelector(".next-slide");
  const overviewPanel = document.querySelector(".overview-panel");
  const imageViewer = document.querySelector(".image-viewer");
  const imageViewerStage = document.querySelector(".image-viewer-stage");
  const imageViewerImage = document.querySelector(".image-viewer-image");
  const imageViewerTitle = document.querySelector(".image-viewer-title");
  const imageViewerScale = document.querySelector(".image-viewer-scale");
  const imageViewerSource = document.querySelector(".image-viewer-source");
  const storedTheme = localStorage.getItem("agent-study-theme");
  const preferredDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  let current = 0;
  let wheelLocked = false;
  let touchStartX = 0;
  let touchStartY = 0;
  let viewerScale = 1;
  let viewerX = 0;
  let viewerY = 0;
  let viewerDragStart = null;
  let viewerReturnFocus = null;

  root.dataset.theme = storedTheme || (preferredDark ? "dark" : "light");

  const numberFromHash = () => {
    const match = window.location.hash.match(/^#slide-(\d+)$/);
    return match ? Number(match[1]) - 1 : 0;
  };

  const clamp = (value) => Math.min(slides.length - 1, Math.max(0, value));

  const updateOverflow = () => {
    for (const slide of slides) {
      const content = slide.querySelector(".slide-content");
      slide.classList.toggle(
        "has-overflow",
        content.scrollHeight > content.clientHeight + 3,
      );
    }
  };

  const showSlide = (next, { updateHash = true } = {}) => {
    current = clamp(next);
    slides.forEach((slide, index) => {
      slide.classList.toggle("is-active", index === current);
      slide.classList.toggle("is-before", index < current);
      slide.setAttribute("aria-hidden", index === current ? "false" : "true");
    });
    overviewItems.forEach((item, index) => {
      item.classList.toggle("is-current", index === current);
    });
    counter.textContent = String(current + 1).padStart(2, "0");
    progress.style.width = `${((current + 1) / slides.length) * 100}%`;
    previousButton.disabled = current === 0;
    nextButton.disabled = current === slides.length - 1;
    slides[current].querySelector(".slide-content").scrollTop = 0;
    if (updateHash) {
      history.replaceState(null, "", `#slide-${current + 1}`);
    }
    document.title = `${slides[current].getAttribute("aria-label")} · Agent Study`;
  };

  const move = (offset) => showSlide(current + offset);

  const toggleOverview = (open = !document.body.classList.contains("overview-open")) => {
    document.body.classList.toggle("overview-open", open);
    overviewPanel.setAttribute("aria-hidden", open ? "false" : "true");
  };

  const applyViewerTransform = () => {
    imageViewerImage.style.transform =
      `translate3d(${viewerX}px, ${viewerY}px, 0) scale(${viewerScale})`;
    imageViewerScale.textContent = `${Math.round(viewerScale * 100)}%`;
  };

  const resetImageViewer = () => {
    viewerScale = 1;
    viewerX = 0;
    viewerY = 0;
    applyViewerTransform();
  };

  const setViewerScale = (nextScale) => {
    viewerScale = Math.min(5, Math.max(1, nextScale));
    if (viewerScale === 1) {
      viewerX = 0;
      viewerY = 0;
    }
    applyViewerTransform();
  };

  const openImageViewer = (image) => {
    const sourceLink = image.closest(".image-link");
    const label = image.alt || "演示图片";
    viewerReturnFocus = document.activeElement;
    imageViewerImage.src = image.currentSrc || image.src;
    imageViewerImage.alt = label;
    imageViewerTitle.textContent = label;
    if (sourceLink?.href) {
      imageViewerSource.href = sourceLink.href;
      imageViewerSource.hidden = false;
    } else {
      imageViewerSource.hidden = true;
      imageViewerSource.removeAttribute("href");
    }
    toggleOverview(false);
    resetImageViewer();
    document.body.classList.add("image-viewer-open");
    imageViewer.setAttribute("aria-hidden", "false");
    document.querySelector('[data-viewer-action="close"]').focus();
  };

  const closeImageViewer = () => {
    document.body.classList.remove("image-viewer-open");
    imageViewer.setAttribute("aria-hidden", "true");
    imageViewerImage.removeAttribute("src");
    resetImageViewer();
    if (viewerReturnFocus instanceof HTMLElement) viewerReturnFocus.focus();
  };

  for (const image of document.querySelectorAll(".slide.has-image img")) {
    const sourceLink = image.closest(".image-link");
    const container = image.closest("p");
    const openViewer = (event) => {
      event.preventDefault();
      event.stopPropagation();
      openImageViewer(image);
    };

    image.title = "点击放大";
    if (sourceLink) {
      sourceLink.setAttribute("aria-label", `放大图片：${image.alt || "演示图片"}`);
      sourceLink.addEventListener("click", openViewer);
    } else {
      image.tabIndex = 0;
      image.setAttribute("role", "button");
      image.setAttribute("aria-label", `放大图片：${image.alt || "演示图片"}`);
      image.addEventListener("click", openViewer);
      image.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") openViewer(event);
      });
    }

    if (container) {
      const zoomButton = document.createElement("button");
      zoomButton.className = "image-zoom-trigger";
      zoomButton.type = "button";
      zoomButton.textContent = "放大";
      zoomButton.setAttribute("aria-label", `放大图片：${image.alt || "演示图片"}`);
      zoomButton.addEventListener("click", openViewer);
      container.append(zoomButton);
    }

    if (!image.complete) image.addEventListener("load", updateOverflow);
  }

  for (const button of document.querySelectorAll("[data-viewer-action]")) {
    button.addEventListener("click", () => {
      const action = button.dataset.viewerAction;
      if (action === "close") closeImageViewer();
      else if (action === "zoom-in") setViewerScale(viewerScale * 1.25);
      else if (action === "zoom-out") setViewerScale(viewerScale / 1.25);
      else if (action === "reset") resetImageViewer();
    });
  }

  imageViewerStage.addEventListener(
    "wheel",
    (event) => {
      event.preventDefault();
      setViewerScale(viewerScale * (event.deltaY < 0 ? 1.12 : 1 / 1.12));
    },
    { passive: false },
  );

  imageViewerStage.addEventListener("dblclick", () => {
    setViewerScale(viewerScale > 1 ? 1 : 2.5);
  });

  imageViewerStage.addEventListener("pointerdown", (event) => {
    if (viewerScale <= 1) return;
    viewerDragStart = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      originX: viewerX,
      originY: viewerY,
    };
    imageViewerStage.classList.add("is-dragging");
    imageViewerStage.setPointerCapture(event.pointerId);
  });

  imageViewerStage.addEventListener("pointermove", (event) => {
    if (!viewerDragStart || event.pointerId !== viewerDragStart.pointerId) return;
    viewerX = viewerDragStart.originX + event.clientX - viewerDragStart.x;
    viewerY = viewerDragStart.originY + event.clientY - viewerDragStart.y;
    applyViewerTransform();
  });

  const stopViewerDrag = (event) => {
    if (!viewerDragStart || event.pointerId !== viewerDragStart.pointerId) return;
    viewerDragStart = null;
    imageViewerStage.classList.remove("is-dragging");
  };

  imageViewerStage.addEventListener("pointerup", stopViewerDrag);
  imageViewerStage.addEventListener("pointercancel", stopViewerDrag);

  previousButton.addEventListener("click", () => move(-1));
  nextButton.addEventListener("click", () => move(1));
  document.querySelector(".overview-toggle").addEventListener("click", () => toggleOverview());
  document.querySelector(".overview-close").addEventListener("click", () => toggleOverview(false));

  overviewItems.forEach((item) => {
    item.addEventListener("click", () => {
      showSlide(Number(item.dataset.targetSlide));
      toggleOverview(false);
    });
  });

  document.querySelector(".fullscreen-toggle").addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.documentElement.requestFullscreen();
    } catch {
      // Browsers may block fullscreen outside a direct user gesture.
    }
  });

  for (const button of document.querySelectorAll(".theme-toggle")) {
    button.addEventListener("click", () => {
      const next = root.dataset.theme === "dark" ? "light" : "dark";
      localStorage.setItem("agent-study-theme", next);
      window.location.reload();
    });
  }

  for (const button of document.querySelectorAll(".copy-code")) {
    button.addEventListener("click", async () => {
      const code = button.parentElement?.querySelector("code")?.textContent ?? "";
      try {
        await navigator.clipboard.writeText(code);
      } catch {
        // Clipboard permission is optional in presentation mode.
      }
    });
  }

  document.addEventListener("keydown", (event) => {
    if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) {
      return;
    }
    if (document.body.classList.contains("image-viewer-open")) {
      if (event.key === "Escape") {
        event.preventDefault();
        closeImageViewer();
      } else if (event.key === "+" || event.key === "=") {
        event.preventDefault();
        setViewerScale(viewerScale * 1.25);
      } else if (event.key === "-") {
        event.preventDefault();
        setViewerScale(viewerScale / 1.25);
      } else if (event.key === "0") {
        event.preventDefault();
        resetImageViewer();
      }
      return;
    }
    if (document.body.classList.contains("overview-open")) {
      if (event.key === "Escape" || event.key.toLowerCase() === "o") {
        event.preventDefault();
        toggleOverview(false);
      }
      return;
    }
    if (["ArrowRight", "ArrowDown", "PageDown", " "].includes(event.key)) {
      event.preventDefault();
      move(1);
    } else if (["ArrowLeft", "ArrowUp", "PageUp"].includes(event.key)) {
      event.preventDefault();
      move(-1);
    } else if (event.key === "Home") {
      event.preventDefault();
      showSlide(0);
    } else if (event.key === "End") {
      event.preventDefault();
      showSlide(slides.length - 1);
    } else if (event.key.toLowerCase() === "o") {
      event.preventDefault();
      toggleOverview(true);
    } else if (event.key.toLowerCase() === "f") {
      event.preventDefault();
      document.querySelector(".fullscreen-toggle").click();
    }
  });

  document.querySelector(".deck").addEventListener(
    "wheel",
    (event) => {
      const content = slides[current].querySelector(".slide-content");
      const down = event.deltaY > 0;
      const canScrollDown =
        content.scrollTop + content.clientHeight < content.scrollHeight - 4;
      const canScrollUp = content.scrollTop > 4;
      if ((down && canScrollDown) || (!down && canScrollUp)) return;
      event.preventDefault();
      if (wheelLocked || Math.abs(event.deltaY) < 18) return;
      wheelLocked = true;
      move(down ? 1 : -1);
      window.setTimeout(() => {
        wheelLocked = false;
      }, 420);
    },
    { passive: false },
  );

  document.querySelector(".deck").addEventListener(
    "touchstart",
    (event) => {
      touchStartX = event.changedTouches[0].clientX;
      touchStartY = event.changedTouches[0].clientY;
    },
    { passive: true },
  );

  document.querySelector(".deck").addEventListener(
    "touchend",
    (event) => {
      const deltaX = event.changedTouches[0].clientX - touchStartX;
      const deltaY = event.changedTouches[0].clientY - touchStartY;
      if (Math.abs(deltaX) < 45 || Math.abs(deltaX) < Math.abs(deltaY)) return;
      move(deltaX < 0 ? 1 : -1);
    },
    { passive: true },
  );

  window.addEventListener("hashchange", () =>
    showSlide(numberFromHash(), { updateHash: false }),
  );
  window.addEventListener("resize", updateOverflow);

  window.addEventListener("load", () => {
    if (window.mermaid) {
      window.mermaid.initialize({
        startOnLoad: false,
        theme: root.dataset.theme === "dark" ? "dark" : "neutral",
        securityLevel: "strict",
        fontFamily: getComputedStyle(root).fontFamily,
      });
      window.mermaid
        .run({ querySelector: ".mermaid" })
        .then(updateOverflow)
        .catch((error) => console.warn("Mermaid rendering failed", error));
    } else {
      updateOverflow();
    }
  });

  current = clamp(numberFromHash());
  showSlide(current, { updateHash: !window.location.hash });
  updateOverflow();
})();
