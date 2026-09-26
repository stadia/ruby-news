import { Controller } from "@hotwired/stimulus"
import { resetFormWithCounter } from "utils/form_helpers"

// Connects to data-controller="post-form"
export default class extends Controller {
  static values = { defaultParentId: Number, defaultAuthorName: String, defaultBodyPreview: String }
  static targets = ["parentId", "replyBanner", "replyLabel", "replyPreview", "body"]

  connect() {
    this.beforeCache = this.beforeCache.bind(this)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.syncReplyState()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  reset(event) {
    if (!event?.detail?.success) return

    resetFormWithCounter(this.element)
    this.clearReplyState()
  }

  beforeCache() {
    resetFormWithCounter(this.element)
    this.clearReplyState()
  }

  activateReply(event) {
    if (!this.hasParentIdTarget) return

    const { parentId, authorName, bodyPreview } = event.detail || {}
    if (!parentId) return

    this.parentIdTarget.value = parentId
    if (this.hasReplyLabelTarget) this.replyLabelTarget.textContent = authorName || ""
    if (this.hasReplyPreviewTarget) this.replyPreviewTarget.textContent = bodyPreview || ""
    this.showReplyBanner()
    this.focusBody()
    this.element.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  cancelReply() {
    this.clearReplyState()
  }

  syncReplyState() {
    if (this.hasParentIdTarget && this.parentIdTarget.value) {
      this.showReplyBanner()
    } else {
      this.hideReplyBanner()
    }
  }

  clearReplyState() {
    if (this.hasParentIdTarget) this.parentIdTarget.value = this.defaultParentIdValue || ""
    if (this.hasReplyLabelTarget) this.replyLabelTarget.textContent = this.defaultAuthorNameValue || ""
    if (this.hasReplyPreviewTarget) this.replyPreviewTarget.textContent = this.defaultBodyPreviewValue || ""
    this.syncReplyState()
  }

  showReplyBanner() {
    if (this.hasReplyBannerTarget) this.replyBannerTarget.classList.remove("hidden")
  }

  hideReplyBanner() {
    if (this.hasReplyBannerTarget) this.replyBannerTarget.classList.add("hidden")
  }

  focusBody() {
    const form = this.element.querySelector("form")
    if (!form) return

    const editable = form.querySelector("[contenteditable='true'], textarea")
    editable?.focus()
  }
}
