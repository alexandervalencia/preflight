import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form", "editButton", "input"]

  edit() {
    this.displayTarget.hidden = true
    this.formTarget.hidden = false
    if (this.hasEditButtonTarget) this.editButtonTarget.hidden = true
    if (this.hasInputTarget) {
      this.inputTarget.focus()
      this.inputTarget.select()
    }
  }

  cancel() {
    this.displayTarget.hidden = false
    this.formTarget.hidden = true
    if (this.hasEditButtonTarget) this.editButtonTarget.hidden = false
  }
}
