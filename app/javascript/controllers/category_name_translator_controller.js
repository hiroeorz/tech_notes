import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "nameEn", "button", "message"]
  static values = {
    url: String,
    translating: String,
    success: String,
    error: String
  }

  async translate() {
    const name = this.nameTarget.value.trim()
    if (name === "") return

    this.setMessage(this.translatingValue, false)
    this.buttonTarget.disabled = true

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ name: name })
      })

      if (!response.ok) {
        const data = await response.json().catch(() => ({}))
        this.setMessage(data.error || this.errorValue, true)
        return
      }

      const data = await response.json()
      this.nameEnTarget.value = data.name_en
      this.setMessage(this.successValue, false)
    } catch {
      this.setMessage(this.errorValue, true)
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  setMessage(text, isError) {
    if (!this.hasMessageTarget) return
    this.messageTarget.textContent = text
    this.messageTarget.hidden = false
    this.messageTarget.style.color = isError ? "var(--color-danger)" : "var(--color-accent)"
  }
}
