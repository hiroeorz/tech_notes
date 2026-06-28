// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

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
    button.addEventListener("click", () => {
      const enabled = document.documentElement.classList.toggle("theme-dark")
      window.localStorage.setItem("theme", enabled ? "dark" : "light")
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
    const escapeHtml = (value) => value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")

    const renderMarkdown = () => {
      let inCode = false
      markdownPreview.innerHTML = markdownSource.value.split("\n").map((line) => {
        if (line.startsWith("```")) {
          inCode = !inCode
          return inCode ? "<pre><code>" : "</code></pre>"
        }
        if (inCode) return `${escapeHtml(line)}\n`
        if (line.startsWith("# ")) return `<h1>${escapeHtml(line.slice(2))}</h1>`
        if (line.startsWith("## ")) return `<h2>${escapeHtml(line.slice(3))}</h2>`
        if (line.startsWith("- ")) return `<li>${escapeHtml(line.slice(2))}</li>`
        if (line.trim() === "") return ""
        return `<p>${escapeHtml(line)}</p>`
      }).join("")
    }

    previewTab.addEventListener("click", () => {
      renderMarkdown()
      markdownSource.hidden = true
      markdownPreview.hidden = false
      previewTab.classList.add("active")
      markdownTab.classList.remove("active")
    })

    markdownTab.addEventListener("click", () => {
      markdownSource.hidden = false
      markdownPreview.hidden = true
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
    const updateBodyStats = () => {
      const value = bodyStatsSource.value
      if (linesOutput) linesOutput.textContent = `Lines: ${value.length === 0 ? 0 : value.split("\n").length}`
      if (wordsOutput) wordsOutput.textContent = `Words: ${value.trim() ? value.trim().split(/\s+/).length : 0}`
      if (charsOutput) charsOutput.textContent = `文字数: ${value.length}`
    }
    bodyStatsSource.addEventListener("input", updateBodyStats)
    updateBodyStats()
  }
})
