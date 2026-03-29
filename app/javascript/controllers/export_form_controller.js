import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["draftField"]

  toggleDraft(event) {
    this.draftFieldTarget.value = event.target.checked ? "1" : "0"
  }
}
