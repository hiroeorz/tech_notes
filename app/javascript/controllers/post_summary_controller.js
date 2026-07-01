import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "body", "excerpt", "button", "message"]
  static values = { url: String }

  async generate() {
    if (!this.hasUrlValue || !this.hasBodyTarget || !this.hasExcerptTarget) return

    if (this.excerptTarget.value.trim() !== "" && !window.confirm("現在の要約をAI生成結果で上書きしますか？")) {
      return
    }

    this.setMessage("要約を生成しています...", false)
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
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "要約を生成できませんでした。")

      this.excerptTarget.value = payload.summary || ""
      this.excerptTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.setMessage("AI要約を反映しました。保存前に内容を確認してください。", false)
    } catch (error) {
      this.setMessage(error.message, true)
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  setMessage(text, error) {
    if (!this.hasMessageTarget) return

    this.messageTarget.hidden = false
    this.messageTarget.textContent = text
    this.messageTarget.classList.toggle("error", error)
  }
}
