import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["layout", "collapseIcon", "expandIcon", "button"]

  toggle() {
    const hidden = this.layoutTarget.classList.toggle("pf-review-layout--tree-hidden")

    this.collapseIconTarget.hidden = hidden
    this.expandIconTarget.hidden = !hidden
    this.buttonTarget.setAttribute("aria-label", hidden ? "Show file tree" : "Hide file tree")

    document.cookie = `pf_tree=${hidden ? "0" : "1"};path=/;max-age=31536000;SameSite=Lax`
    const url = new URL(window.location)
    url.searchParams.set("tree", hidden ? "0" : "1")
    history.replaceState(null, "", url)
  }
}
