// 감소 동작을 켠 사용자에게는 부드러운 스크롤 대신 즉시 이동한다(DESIGN.md 접근성 기준).
// scrollIntoView에 behavior를 직접 넘기면 CSS의 prefers-reduced-motion이 적용되지 않는다.
export function scrollBehavior() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
}
