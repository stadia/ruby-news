import { Controller } from "@hotwired/stimulus"

const INLINE_FORM_ID = "inline_reply_form"

// Connects to data-controller="thread-reply"
// 상세 화면에서 하위 답글의 답글 폼을 그 답글 바로 아래에 연다. root에 대한 답글은
// 원문 아래의 폼을 쓴다. 한 번에 inline 폼 하나만 연다.
export default class extends Controller {
  static values = { rootId: Number }
  static targets = ["template", "rootComposer"]

  open(event) {
    const parentId = Number(event.detail?.parentId)
    if (!parentId) return

    if (parentId === this.rootIdValue) {
      this.close()
      this.focusRootComposer()
      return
    }

    const card = document.getElementById(`post_${parentId}`)
    if (!card || !this.element.contains(card) || !this.hasTemplateTarget) return

    const current = this.inlineForm
    const toggling = current && current.previousElementSibling === card
    this.close()
    if (toggling) return

    const node = this.templateTarget.content.firstElementChild.cloneNode(true)
    const parentField = node.querySelector("input[name='post[parent_id]']")
    if (parentField) parentField.value = parentId
    card.after(node)
    this.focusEditor(node)
    node.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  close() {
    this.inlineForm?.remove()
  }

  get inlineForm() {
    return this.element.querySelector(`#${INLINE_FORM_ID}`)
  }

  focusRootComposer() {
    if (!this.hasRootComposerTarget) return

    this.rootComposerTarget.scrollIntoView({ behavior: "smooth", block: "center" })
    this.focusEditor(this.rootComposerTarget)
  }

  // Lexxy는 삽입된 뒤 초기화되므로, 편집 영역이 생길 때까지 기다렸다 포커스한다.
  focusEditor(container) {
    const focus = () => {
      const editable = container.querySelector("[contenteditable='true'], textarea")
      if (editable) editable.focus()
      else container.querySelector("a")?.focus()
      return Boolean(editable)
    }
    if (focus()) return

    container.querySelector("lexxy-editor")?.addEventListener("lexxy:initialize", focus, { once: true })
  }
}
