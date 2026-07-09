import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  change(event) {
    const locale = event.target.value
    if (!locale) return

    // Remove existing locale prefix from path and navigate to new locale URL
    const path = window.location.pathname.replace(/^\/(en|ja)(\/|$)/, "/")
    const newPath = `/${locale}${path.startsWith("/") ? path : "/" + path}`
    window.location.href = `${newPath}${window.location.search}`
  }
}
