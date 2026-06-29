// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("change", (event) => {
  const input = event.target
  if (!(input instanceof HTMLInputElement) || !input.matches("[data-profile-image-input]")) return

  const file = input.files?.[0]
  if (!file || !file.type.startsWith("image/")) return

  const container = input.closest("[data-profile-image-preview-container]")
  if (!container) return

  const reader = new FileReader()
  reader.addEventListener("load", () => {
    let image = container.querySelector("[data-profile-image-preview]")
    const placeholder = container.querySelector("[data-profile-image-placeholder]")

    if (!image) {
      image = document.createElement("img")
      image.alt = "プロフィール画像"
      image.className = "settings-avatar-image"
      image.dataset.profileImagePreview = "true"

      if (placeholder) {
        placeholder.replaceWith(image)
      } else {
        input.before(image)
      }
    }

    image.src = reader.result
    document.querySelector("[data-profile-image-save-notice]")?.removeAttribute("hidden")
  })
  reader.readAsDataURL(file)
})

document.addEventListener("turbo:load", () => {
  const savedTheme = window.localStorage.getItem("theme")
  const defaultTheme = document.documentElement.dataset.defaultTheme || "light"
  document.documentElement.classList.toggle("theme-dark", (savedTheme || defaultTheme) === "dark")

  document.querySelectorAll("[data-password-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      const input = button.closest(".password-field")?.querySelector("input")
      if (!input) return
      input.type = input.type === "password" ? "text" : "password"
    })
  })

  document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
    button.setAttribute("aria-pressed", document.documentElement.classList.contains("theme-dark") ? "true" : "false")
    button.addEventListener("click", () => {
      const enabled = document.documentElement.classList.toggle("theme-dark")
      window.localStorage.setItem("theme", enabled ? "dark" : "light")
      button.setAttribute("aria-pressed", enabled ? "true" : "false")
    })
  })

  document.querySelectorAll("[data-search-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      const panel = document.querySelector("[data-search-panel]")
      if (!panel) return
      panel.hidden = !panel.hidden
      if (!panel.hidden) panel.querySelector("input")?.focus()
    })
  })

  document.querySelectorAll("[data-live-count-input]").forEach((input) => {
    const output = document.querySelector(`[data-live-count-output="${input.dataset.liveCountInput}"]`)
    const max = input.dataset.liveCountMax
    const update = () => {
      if (output) output.textContent = `${input.value.length} / ${max}`
    }
    input.addEventListener("input", update)
    update()
  })

  document.querySelectorAll("[data-tag-input]").forEach((input) => {
    const preview = input.closest("label")?.querySelector("[data-tag-preview]")
    if (!preview) return
    const renderTags = () => {
      preview.innerHTML = ""
      input.value.split(",").map((value) => value.trim()).filter(Boolean).forEach((tagName) => {
        const chip = document.createElement("span")
        chip.className = "chip"
        chip.textContent = tagName
        preview.appendChild(chip)
      })
    }
    input.addEventListener("input", renderTags)
    renderTags()
  })

  const markdownSource = document.querySelector("[data-markdown-source]")
  const markdownPreview = document.querySelector("[data-markdown-preview]")
  const markdownTab = document.querySelector("[data-editor-tab='markdown']")
  const previewTab = document.querySelector("[data-editor-tab='preview']")

  if (markdownSource && markdownPreview && markdownTab && previewTab) {
    const previewUrl = markdownPreview.closest("[data-markdown-preview-url]")?.dataset.markdownPreviewUrl

    const escapeHtml = (value) => value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;")

    const safeHref = (href) => (
      href.startsWith("http://") ||
      href.startsWith("https://") ||
      href.startsWith("mailto:") ||
      href.startsWith("/") ||
      href.startsWith("#")
    )

    const safeImageSource = (source) => (
      source.startsWith("http://") ||
      source.startsWith("https://") ||
      source.startsWith("/") ||
      /^[\w./-]+$/.test(source)
    )

    const inlineMarkdown = (value) => escapeHtml(value)
      .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_match, label, href) => {
        if (!safeHref(href)) return `[${label}](${escapeHtml(href)})`
        return `<a href="${escapeHtml(href)}" rel="noreferrer">${label}</a>`
      })
      .replace(/`([^`]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/\*([^*]+)\*/g, "<em>$1</em>")

    const tableLine = (line) => line.startsWith("|") && line.endsWith("|")
    const tableSeparator = (line) => /^\|[\s:|-]+\|$/.test(line)
    const tableCells = (line) => line.slice(1, -1).split("|").map((cell) => cell.trim())

    const renderTable = (rows) => {
      if (rows.length === 0) return ""
      const [header, ...body] = rows
      const thead = `<thead><tr>${header.map((cell) => `<th>${inlineMarkdown(cell)}</th>`).join("")}</tr></thead>`
      const tbody = body.length === 0 ? "" : `<tbody>${body.map((row) => `<tr>${row.map((cell) => `<td>${inlineMarkdown(cell)}</td>`).join("")}</tr>`).join("")}</tbody>`
      return `<table class="markdown-table">${thead}${tbody}</table>`
    }

    const renderImage = (alt, source) => {
      if (!safeImageSource(source)) return `<p>${escapeHtml(`![${alt}](${source})`)}</p>`
      return `<figure class="article-image"><img src="${escapeHtml(source)}" alt="${escapeHtml(alt)}" loading="lazy"><figcaption>${escapeHtml(alt)}</figcaption></figure>`
    }

    const renderListItem = (text) => {
      const task = text.match(/^\[( |x|X)\]\s+(.+)$/)
      if (!task) return `<li>${inlineMarkdown(text)}</li>`
      return `<li class="task-list-item"><input type="checkbox" disabled${task[1].toLowerCase() === "x" ? " checked" : ""}>${inlineMarkdown(task[2])}</li>`
    }

    const renderMarkdown = () => {
      let inCode = false
      let listType = null
      let tableRows = []
      const html = []
      const closeList = () => {
        if (!listType) return
        html.push(`</${listType}>`)
        listType = null
      }
      const flushTable = () => {
        if (tableRows.length === 0) return
        html.push(renderTable(tableRows))
        tableRows = []
      }
      const openList = (type) => {
        if (listType === type) return
        closeList()
        html.push(`<${type}>`)
        listType = type
      }

      markdownSource.value.split("\n").forEach((line) => {
        if (line.startsWith("```")) {
          flushTable()
          closeList()
          inCode = !inCode
          html.push(inCode ? "<pre><code>" : "</code></pre>")
          return
        }
        if (inCode) {
          html.push(`${escapeHtml(line)}\n`)
          return
        }
        const image = line.match(/^!\[(.*?)\]\((.*?)\)$/)
        if (image) {
          flushTable()
          closeList()
          html.push(renderImage(image[1], image[2]))
          return
        }
        if (tableLine(line)) {
          closeList()
          if (!tableSeparator(line)) tableRows.push(tableCells(line))
          return
        }
        flushTable()
        const unordered = line.match(/^\s*[-*+]\s+(.+)$/)
        const ordered = line.match(/^\s*\d+\.\s+(.+)$/)
        if (unordered) {
          openList("ul")
          html.push(renderListItem(unordered[1]))
          return
        }
        if (ordered) {
          openList("ol")
          html.push(`<li>${inlineMarkdown(ordered[1])}</li>`)
          return
        }
        closeList()
        if (line.startsWith("# ")) html.push(`<h1>${inlineMarkdown(line.slice(2))}</h1>`)
        else if (line.startsWith("## ")) html.push(`<h2>${inlineMarkdown(line.slice(3))}</h2>`)
        else if (line.startsWith("### ")) html.push(`<h3>${inlineMarkdown(line.slice(4))}</h3>`)
        else if (line.startsWith("> ")) html.push(`<aside class="note-box"><strong>ポイント:</strong> ${inlineMarkdown(line.slice(2))}</aside>`)
        else if (line.trim() === "") html.push("")
        else html.push(`<p>${inlineMarkdown(line)}</p>`)
      })
      flushTable()
      closeList()
      if (inCode) html.push("</code></pre>")
      markdownPreview.innerHTML = html.join("")
    }

    const renderServerPreview = async () => {
      if (!previewUrl) return false
      const token = document.querySelector("meta[name='csrf-token']")?.content
      const body = new URLSearchParams({ body: markdownSource.value })
      const response = await fetch(previewUrl, {
        method: "POST",
        headers: {
          "Accept": "text/html",
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "X-CSRF-Token": token || ""
        },
        body
      })
      if (!response.ok) return false
      markdownPreview.innerHTML = await response.text()
      return true
    }

    const openPreview = async () => {
      try {
        if (!await renderServerPreview()) renderMarkdown()
      } catch (_error) {
        renderMarkdown()
      }
      markdownSource.hidden = true
      markdownPreview.hidden = false
      markdownPreview.closest(".textarea-shell")?.classList.add("preview-mode")
      previewTab.classList.add("active")
      markdownTab.classList.remove("active")
      markdownPreview.closest(".markdown-editor")?.scrollIntoView({ behavior: "smooth", block: "start" })
    }

    previewTab.addEventListener("click", openPreview)

    document.querySelectorAll("[data-open-editor-preview]").forEach((button) => {
      button.addEventListener("click", openPreview)
    })

    markdownTab.addEventListener("click", () => {
      markdownSource.hidden = false
      markdownPreview.hidden = true
      markdownPreview.closest(".textarea-shell")?.classList.remove("preview-mode")
      markdownTab.classList.add("active")
      previewTab.classList.remove("active")
    })

    const snippets = {
      bold: ["**", "**", "太字"],
      italic: ["*", "*", "斜体"],
      code: ["`", "`", "code"],
      list: ["- ", "", "リスト項目"],
      ordered: ["1. ", "", "番号付き項目"],
      quote: ["> ", "", "引用"],
      check: ["- [ ] ", "", "確認項目"],
      image: ["![説明](", ")", "images/example.png"],
      table: ["| 項目 | 内容 |\n| --- | --- |\n| ", " |  |\n", "値"],
      link: ["[リンクテキスト](", ")", "https://example.com"]
    }

    document.querySelectorAll("[data-md-action]").forEach((button) => {
      button.addEventListener("click", () => {
        const [before, after, fallback] = snippets[button.dataset.mdAction] || ["", "", ""]
        const start = markdownSource.selectionStart
        const end = markdownSource.selectionEnd
        const selected = markdownSource.value.slice(start, end) || fallback
        const inserted = `${before}${selected}${after}`
        markdownSource.setRangeText(inserted, start, end, "end")
        markdownSource.dispatchEvent(new Event("input", { bubbles: true }))
        markdownSource.focus()
      })
    })
  }

  const bodyStatsSource = document.querySelector("[data-body-stats-source]")
  if (bodyStatsSource) {
    const linesOutput = document.querySelector("[data-body-stat='lines']")
    const wordsOutput = document.querySelector("[data-body-stat='words']")
    const charsOutput = document.querySelector("[data-body-stat='chars']")
    const lineNumbers = document.querySelector(".line-numbers")

    const updateBodyStats = () => {
      const value = bodyStatsSource.value
      const lineCount = value.length === 0 ? 1 : value.split("\n").length
      if (linesOutput) linesOutput.textContent = `Lines: ${lineCount}`
      if (wordsOutput) wordsOutput.textContent = `Words: ${value.trim() ? value.trim().split(/\s+/).length : 0}`
      if (charsOutput) charsOutput.textContent = `文字数: ${value.length}`

      if (lineNumbers) {
        const targetCount = Math.max(lineCount + 5, 44)
        if (lineNumbers.children.length !== targetCount) {
          let html = ""
          for (let i = 1; i <= targetCount; i += 1) {
            html += `<span>${i}</span>`
          }
          lineNumbers.innerHTML = html
        }
      }
    }

    bodyStatsSource.addEventListener("input", updateBodyStats)
    bodyStatsSource.addEventListener("scroll", () => {
      if (lineNumbers) lineNumbers.scrollTop = bodyStatsSource.scrollTop
    })
    updateBodyStats()
  }

  const publishModalBackdrop = document.querySelector("[data-publish-modal-backdrop]")
  if (publishModalBackdrop) {
    document.querySelectorAll("[data-open-publish-modal]").forEach((button) => {
      button.addEventListener("click", () => {
        publishModalBackdrop.hidden = false
      })
    })

    document.querySelectorAll("[data-close-publish-modal]").forEach((button) => {
      button.addEventListener("click", () => {
        publishModalBackdrop.hidden = true
      })
    })

    publishModalBackdrop.addEventListener("click", (event) => {
      if (event.target === publishModalBackdrop) {
        publishModalBackdrop.hidden = true
      }
    })
  }
})
