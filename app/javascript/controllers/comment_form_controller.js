import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit", "turnstile"]
  static values = { siteKey: String }

  connect() {
    this.disableButton()
    this.renderWidget()
  }

  disconnect() {
    if (this.widgetId != null && typeof turnstile !== "undefined") {
      turnstile.remove(this.widgetId)
    }
  }

  disableButton() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
    }
  }

  enableButton() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
    }
  }

  renderWidget() {
    if (typeof turnstile !== "undefined") {
      this.widgetId = turnstile.render(this.turnstileTarget, {
        sitekey: this.siteKeyValue,
        callback: () => this.enableButton(),
        "expired-callback": () => this.disableButton(),
        "error-callback": () => this.disableButton()
      })
    } else {
      setTimeout(() => this.renderWidget(), 200)
    }
  }
}
