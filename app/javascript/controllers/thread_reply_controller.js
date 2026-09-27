import { Controller } from "@hotwired/stimulus"
import { scrollBehavior } from "utils/motion"

const INLINE_FORM_ID = "inline_reply_form"
const REPLY_BUTTON = "button[data-action='feed-reply#activate']"

// Connects to data-controller="thread-reply"
// 상세 화면에서 하위 답글의 답글 폼을 그 답글 바로 아래에 연다. root 답글은 원문
// 아래 폼을 쓴다. inline 폼은 하나만 두고, 대상을 바꾸면 작성 중인 본문을 새 대상
// 아래로 옮긴다. 폼을 지우는 것은 취소 버튼과 Turbo 캐시 정리뿐이다.
export default class extends Controller {
  static values = { rootId: Number }
  static targets = ["template", "rootComposer"]

  // 저장에 실패해 서버가 inline 폼을 다시 그렸다면, 전체 페이지 POST로 맨 위에
  // 돌아온 화면을 그 폼으로 옮긴다.
  connect() {
    const form = this.inlineForm
    if (!form) return

    form.scrollIntoView({ block: "center" })
    this.focusEditor(form)
  }

  open(event) {
    const parentId = Number(event.detail?.parentId)
    if (!parentId) return

    if (parentId === this.rootIdValue) {
      this.focusRootComposer()
      return
    }

    const card = document.getElementById(`post_${parentId}`)
    if (!card || !this.element.contains(card) || !this.hasTemplateTarget) return

    const current = this.inlineForm
    if (current && current.previousElementSibling === card) {
      this.focusEditor(current)
      return
    }

    const node = this.buildForm(parentId, current)
    current?.remove()
    card.after(node)
    this.focusEditor(node)
    node.scrollIntoView({ behavior: scrollBehavior(), block: "nearest" })
  }

  close(event) {
    const form = this.inlineForm
    if (!form) return

    const card = form.previousElementSibling
    form.remove()
    // 취소 버튼으로 닫았을 때만 포커스를 대상 답글 버튼으로 돌려준다.
    if (event?.type === "click") card?.querySelector(REPLY_BUTTON)?.focus()
  }

  get inlineForm() {
    return this.element.querySelector(`#${INLINE_FORM_ID}`)
  }

  // 템플릿을 새로 복제해 Lexxy를 새로 초기화한다. 기존 폼의 본문은 value 속성으로
  // 넘겨, 초기화될 때 그대로 불러오게 한다. 이전 대상에 대한 오류 표시는 옮기지 않는다.
  buildForm(parentId, previous) {
    const node = this.templateTarget.content.firstElementChild.cloneNode(true)
    const parentField = node.querySelector("input[name='post[parent_id]']")
    if (parentField) parentField.value = parentId

    const draft = previous?.querySelector("lexxy-editor")?.value
    const editor = node.querySelector("lexxy-editor")
    if (draft && editor) editor.setAttribute("value", draft)
    return node
  }

  focusRootComposer() {
    if (!this.hasRootComposerTarget) return

    this.rootComposerTarget.scrollIntoView({ behavior: scrollBehavior(), block: "center" })
    this.focusEditor(this.rootComposerTarget)
  }

  // 새로 삽입한 Lexxy는 비동기로 초기화되므로 편집 영역이 생기면 포커스한다.
  // 비로그인 사용자에게는 편집 영역 대신 로그인 링크에 포커스한다.
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
