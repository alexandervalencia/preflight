import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]

  open() {
    this.overlayTarget.hidden = false
  }

  close() {
    this.overlayTarget.hidden = true
  }

  closeOnBackdrop(event) {
    if (event.target === this.overlayTarget) {
      this.overlayTarget.hidden = true
    }
  }
}
