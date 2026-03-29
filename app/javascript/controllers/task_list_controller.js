import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, baseBranch: String, description: String }

  toggle(event) {
    const checkbox = event.target
    const taskIndex = parseInt(checkbox.dataset.taskIndex, 10)

    let count = -1
    const updated = this.descriptionValue.replace(/- \[(x| )\]/gi, (match, state) => {
      count++
      if (count === taskIndex) {
        return state.trim() ? "- [ ]" : "- [x]"
      }
      return match
    })

    this.descriptionValue = updated

    // Sync the edit textarea if open
    const textarea = document.querySelector("[data-role='description-form'] textarea")
    if (textarea) textarea.value = updated

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: `pull_request[description]=${encodeURIComponent(updated)}&pull_request[base_branch]=${encodeURIComponent(this.baseBranchValue)}`
    })
  }
}
