import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  change(event) {
    const locale = event.target.value
    if (!locale) return

    if (window.location.pathname.startsWith("/oauth/")) {
      document.cookie = `locale=${locale}; path=/; max-age=630720000; SameSite=Lax`
      window.location.href = `${window.location.pathname}${window.location.search}`
      return
    }

    // Remove existing locale prefix from path and navigate to new locale URL
    const path = window.location.pathname.replace(/^\/(en|ja)(\/|$)/, "/")
    const newPath = `/${locale}${path.startsWith("/") ? path : "/" + path}`
    window.location.href = `${newPath}${window.location.search}`
  }
}
