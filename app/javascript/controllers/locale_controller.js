import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  change(event) {
    const locale = event.target.value
    if (!locale) return

    const form = this.element
    const action = form.action

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "locale"
    input.value = locale
    form.appendChild(input)

    form.submit()
  }
}
