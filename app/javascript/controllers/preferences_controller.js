import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const params = new URLSearchParams(window.location.search)
    ;["layout", "compact", "tree"].forEach((key) => {
      if (params.has(key)) {
        document.cookie = `pf_${key}=${params.get(key)};path=/;max-age=31536000;SameSite=Lax`
      }
    })
  }
}
