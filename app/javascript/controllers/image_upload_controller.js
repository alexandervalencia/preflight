import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "dropzone", "fileInput"]

  connect() {
    this.textareaTarget.addEventListener("paste", this.handlePaste.bind(this))
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("pf-dropzone--active")
  }

  dragleave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("pf-dropzone--active")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("pf-dropzone--active")
    const files = event.dataTransfer.files
    if (files.length > 0) this.uploadFile(files[0])
  }

  selectFile() {
    this.fileInputTarget.click()
  }

  fileSelected(event) {
    const file = event.target.files[0]
    if (file) this.uploadFile(file)
  }

  handlePaste(event) {
    const items = event.clipboardData?.items
    if (!items) return

    for (const item of items) {
      if (item.type.startsWith("image/")) {
        event.preventDefault()
        this.uploadFile(item.getAsFile())
        return
      }
    }
  }

  async uploadFile(file) {
    const formData = new FormData()
    formData.append("file", file)

    const uploadUrl = this.element.dataset.imageUploadUrl

    try {
      const response = await fetch(uploadUrl, {
        method: "POST",
        body: formData,
        headers: { "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content }
      })

      if (response.ok) {
        const data = await response.json()
        this.insertAtCursor(data.markdown)
      } else {
        const error = await response.json()
        alert(error.error || "Upload failed")
      }
    } catch {
      alert("Upload failed — server may not be running")
    }
  }

  insertAtCursor(text) {
    const textarea = this.textareaTarget
    const start = textarea.selectionStart
    const end = textarea.selectionEnd
    const before = textarea.value.substring(0, start)
    const after = textarea.value.substring(end)
    const needsNewline = before.length > 0 && !before.endsWith("\n") ? "\n" : ""

    textarea.value = before + needsNewline + text + "\n" + after
    textarea.selectionStart = textarea.selectionEnd = start + needsNewline.length + text.length + 1
    textarea.focus()
  }
}
