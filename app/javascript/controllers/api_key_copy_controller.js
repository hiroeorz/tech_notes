import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]
  static values = { copied: String }

  copy() {
    const text = this.sourceTarget.textContent.trim()

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(
        () => this.showCopied(),
        () => this.copyWithFallback(text)
      )
    } else {
      this.copyWithFallback(text)
    }
  }

  copyWithFallback(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()

    try {
      if (document.execCommand("copy")) {
        this.showCopied()
      }
    } catch {
    } finally {
      document.body.removeChild(textarea)
    }
  }

  showCopied() {
    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = this.copiedValue
    this.buttonTarget.disabled = true

    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.buttonTarget.textContent = original
      this.buttonTarget.disabled = false
    }, 1500)
  }
}
