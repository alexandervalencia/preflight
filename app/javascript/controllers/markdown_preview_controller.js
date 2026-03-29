import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["writeTab", "previewTab", "writePanel", "previewPanel", "textarea"]
  static values = { url: String }

  write() {
    this.writePanelTarget.hidden = false
    this.previewPanelTarget.hidden = true
    this.writeTabTarget.classList.add("pf-editor-tab--active")
    this.previewTabTarget.classList.remove("pf-editor-tab--active")
  }

  preview() {
    this.writePanelTarget.hidden = true
    this.previewPanelTarget.hidden = false
    this.previewTabTarget.classList.add("pf-editor-tab--active")
    this.writeTabTarget.classList.remove("pf-editor-tab--active")

    this.previewPanelTarget.innerHTML = '<p style="color: var(--pf-text-muted)">Loading preview...</p>'

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify({ text: this.textareaTarget.value })
    })
    .then(r => r.json())
    .then(data => {
      this.previewPanelTarget.innerHTML = data.html || '<p style="color: var(--pf-text-muted)">Nothing to preview.</p>'
    })
    .catch(() => {
      this.previewPanelTarget.innerHTML = '<p style="color: var(--pf-danger-text)">Preview failed.</p>'
    })
  }
}
