import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "titleEn", "bio", "bioEn", "button", "message"]
  static values = {
    url: String,
    translating: String,
    success: String,
    error: String
  }

  async translate() {
    const title = this.titleTarget.value.trim()
    const bio = this.bioTarget.value.trim()
    if (title === "" && bio === "") return

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
        body: JSON.stringify({ profile_title: title, profile_bio: bio })
      })

      if (!response.ok) {
        const data = await response.json().catch(() => ({}))
        this.setMessage(data.error || this.errorValue, true)
        return
      }

      const data = await response.json()
      if (this.hasTitleEnTarget && data.profile_title_en) {
        this.titleEnTarget.value = data.profile_title_en
      }
      if (this.hasBioEnTarget && data.profile_bio_en) {
        this.bioEnTarget.value = data.profile_bio_en
      }
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
