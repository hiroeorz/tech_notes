import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "body", "excerpt", "slug", "button", "slugButton", "message", "slugMessage"]
  static values = {
    url: String,
    slugUrl: String,
    confirmOverwriteExcerpt: String,
    generatingExcerpt: String,
    excerptSuccess: String,
    excerptError: String,
    confirmOverwriteSlug: String,
    generatingSlug: String,
    slugSuccess: String,
    slugError: String,
    errorJson: String,
    error401: String,
    errorHtml: String
  }

  async generate() {
    if (!this.hasUrlValue || !this.hasBodyTarget || !this.hasExcerptTarget) return

    if (this.excerptTarget.value.trim() !== "" && !window.confirm(this.confirmOverwriteExcerptValue)) {
      return
    }

    this.setMessage(this.generatingExcerptValue, false)
    this.buttonTarget.disabled = true

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({
          title: this.hasTitleTarget ? this.titleTarget.value : "",
          body: this.bodyTarget.value
        })
      })
      const payload = await this.parseResponse(response)
      if (!response.ok) throw new Error(payload.error || this.excerptErrorValue)

      this.excerptTarget.value = payload.summary || ""
      this.excerptTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.setMessage(this.excerptSuccessValue, false)
    } catch (error) {
      this.setMessage(error.message, true)
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  async generateSlug() {
    if (!this.hasSlugUrlValue || !this.hasSlugTarget) return

    if (this.slugTarget.value.trim() !== "" && !window.confirm(this.confirmOverwriteSlugValue)) {
      return
    }

    this.setMessageFor(this.slugMessageTarget, this.generatingSlugValue, false)
    this.slugButtonTarget.disabled = true

    try {
      const response = await fetch(this.slugUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({
          title: this.hasTitleTarget ? this.titleTarget.value : "",
          body: this.hasBodyTarget ? this.bodyTarget.value : ""
        })
      })
      const payload = await this.parseResponse(response, this.slugErrorValue)
      if (!response.ok) throw new Error(payload.error || this.slugErrorValue)

      this.slugTarget.value = payload.slug || ""
      this.slugTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.setMessageFor(this.slugMessageTarget, this.slugSuccessValue, false)
    } catch (error) {
      this.setMessageFor(this.slugMessageTarget, error.message, true)
    } finally {
      this.slugButtonTarget.disabled = false
    }
  }

  setMessage(text, error) {
    if (!this.hasMessageTarget) return

    this.setMessageFor(this.messageTarget, text, error)
  }

  setMessageFor(target, text, error) {
    if (!target) return

    target.hidden = false
    target.textContent = text
    target.classList.toggle("error", error)
  }

  async parseResponse(response, fallbackMessage = null) {
    const contentType = response.headers.get("Content-Type") || ""
    if (contentType.includes("application/json")) {
      try {
        return await response.json()
      } catch (_error) {
        return { error: this.errorJsonValue }
      }
    }

    const text = await response.text()
    if (response.status === 401) return { error: this.error401Value }
    if (text.includes("<!doctype") || text.includes("<html")) {
      return { error: this.errorHtmlValue }
    }

    return { error: text.trim() || fallbackMessage || this.excerptErrorValue }
  }
}
