import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "button", "buttonLabel", "panel", "audio",
    "playButton", "playIcon", "onairDot",
    "progress", "currentTime", "duration", "errorMessage"
  ]

  static values = { open: Boolean, playing: Boolean }

  togglePanel() {
    this.openValue = !this.openValue
    this.panelTarget.hidden = !this.openValue

    if (this.openValue) {
      this.buttonLabelTarget.textContent = this.element.dataset.closeLabel
    } else {
      this.buttonLabelTarget.textContent = this.element.dataset.openLabel
      if (this.playingValue) this._stop()
    }
  }

  togglePlay() {
    if (this.audioTarget.paused) {
      this._play()
    } else {
      this._pause()
    }
  }

  seek(event) {
    const audio = this.audioTarget
    if (audio.duration) {
      audio.currentTime = (parseFloat(event.target.value) / 100) * audio.duration
    }
  }

  updateProgress() {
    const audio = this.audioTarget
    if (!audio.duration) return
    const pct = (audio.currentTime / audio.duration) * 100
    this.progressTarget.value = pct
    this.currentTimeTarget.textContent = this._formatTime(audio.currentTime)
  }

  onMetadataLoaded() {
    this.durationTarget.textContent = this._formatTime(this.audioTarget.duration)
    this.progressTarget.max = 100
  }

  onEnded() {
    this._stop()
  }

  onError() {
    this.errorMessageTarget.hidden = false
    this.errorMessageTarget.textContent = this.element.dataset.errorMessage
  }

  _play() {
    const promise = this.audioTarget.play()
    if (promise !== undefined) {
      promise.catch(() => {
        this.onError()
      })
    }
    this.playingValue = true
    this.playIconTarget.textContent = "\u23F8"
    this.onairDotTarget.classList.add("active")
    this.playButtonTarget.setAttribute("aria-label", this.element.dataset.pauseLabel)
  }

  _pause() {
    this.audioTarget.pause()
    this.playingValue = false
    this.playIconTarget.textContent = "\u25B6"
    this.onairDotTarget.classList.remove("active")
    this.playButtonTarget.setAttribute("aria-label", this.element.dataset.playLabel)
  }

  _stop() {
    this.audioTarget.pause()
    this.audioTarget.currentTime = 0
    this.playingValue = false
    this.playIconTarget.textContent = "\u25B6"
    this.onairDotTarget.classList.remove("active")
    this.playButtonTarget.setAttribute("aria-label", this.element.dataset.playLabel)
    this.progressTarget.value = 0
    this.currentTimeTarget.textContent = "0:00"
  }

  _formatTime(seconds) {
    const m = Math.floor(seconds / 60)
    const s = Math.floor(seconds % 60)
    return `${m}:${s.toString().padStart(2, "0")}`
  }
}
