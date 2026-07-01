import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "body", "excerpt", "slug", "button", "slugButton", "message", "slugMessage"]
  static values = { url: String, slugUrl: String }

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
      const payload = await this.parseResponse(response)
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

  async generateSlug() {
    if (!this.hasSlugUrlValue || !this.hasSlugTarget) return

    if (this.slugTarget.value.trim() !== "" && !window.confirm("現在のスラッグをAI生成結果で上書きしますか？")) {
      return
    }

    this.setMessageFor(this.slugMessageTarget, "スラッグを生成しています...", false)
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
      const payload = await this.parseResponse(response, "スラッグを生成できませんでした。")
      if (!response.ok) throw new Error(payload.error || "スラッグを生成できませんでした。")

      this.slugTarget.value = payload.slug || ""
      this.slugTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.setMessageFor(this.slugMessageTarget, "AIスラッグを反映しました。保存前に内容を確認してください。", false)
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

  async parseResponse(response, fallbackMessage = "要約を生成できませんでした。") {
    const contentType = response.headers.get("Content-Type") || ""
    if (contentType.includes("application/json")) {
      try {
        return await response.json()
      } catch (_error) {
        return { error: "サーバーから不正なJSONレスポンスが返りました。サーバーログを確認してください。" }
      }
    }

    const text = await response.text()
    if (response.status === 401) return { error: "ログインし直してから実行してください。" }
    if (text.includes("<!doctype") || text.includes("<html")) {
      return { error: "サーバーからHTMLエラーページが返りました。ログイン状態やサーバーログを確認してください。" }
    }

    return { error: text.trim() || fallbackMessage }
  }
}
