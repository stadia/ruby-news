/**
 * Resets a form and its character counter
 * @param {HTMLElement} element - The parent element containing the form
 * @returns {boolean} - True if reset was successful, false otherwise
 */
export function resetFormWithCounter(element) {
  if (!element) return false

  const form = element.querySelector("form")
  if (!form) return false

  // Reset all form fields
  form.reset()

  // Reset character counter if present
  const counter = form.querySelector("[data-character-counter-target='counter']")
  if (counter) {
    counter.textContent = "0"
    counter.classList.remove("text-warning-text", "text-danger-text")
    counter.classList.add("text-content-muted")
  }

  return true
}
