import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]

  toggle(event) {
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.type === "keydown" && event.key === " ") event.preventDefault()

    const header = this.element.querySelector(".mobile-toc-header")
    const currentlyExpanded = header.getAttribute("aria-expanded") === "true"

    header.setAttribute("aria-expanded", !currentlyExpanded)
    this.bodyTarget.hidden = currentlyExpanded
  }
}
