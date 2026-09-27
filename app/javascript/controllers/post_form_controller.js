import { Controller } from "@hotwired/stimulus"
import { resetFormWithCounter } from "utils/form_helpers"
import { scrollBehavior } from "utils/motion"

// Connects to data-controller="post-form"
export default class extends Controller {
  static values = { defaultParentId: Number }
  static targets = ["parentId", "replyBanner", "replyLabel", "replyPreview", "body"]

  connect() {
    this.beforeCache = this.beforeCache.bind(this)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.syncReplyState()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  submit(event) {
    const form = event.target
    if (form.dataset.turbo !== "false") return
    if (this.submitting) {
      event.preventDefault()
      return
    }
    this.submitting = true
    form.querySelectorAll("[type='submit']").forEach(button => { button.disabled = true })
  }

  reset(event) {
    if (!event?.detail?.success) return

    resetFormWithCounter(this.element)
    this.clearReplyState()
  }

  beforeCache() {
    this.submitting = false
    this.element.querySelectorAll("[type='submit']").forEach(button => { button.disabled = false })
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
    this.element.scrollIntoView({ behavior: scrollBehavior(), block: "center" })
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
    // 상세 root 폼은 root로 되돌리고, 피드에서는 답글 모드를 해제한다.
    if (this.hasParentIdTarget) this.parentIdTarget.value = this.defaultParentIdValue || ""
    if (this.hasReplyLabelTarget) this.replyLabelTarget.textContent = ""
    if (this.hasReplyPreviewTarget) this.replyPreviewTarget.textContent = ""
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
