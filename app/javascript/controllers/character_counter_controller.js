import CharacterCounter from "@stimulus-components/character-counter"

// Connects to data-controller="character-counter"
export default class extends CharacterCounter {
  static targets = ["input", "counter"]
  static values = {
    countdown: Boolean,
    maxLength: Number,
    warningThreshold: { type: Number, default: 0.8 },
    dangerThreshold: { type: Number, default: 0.9 }
  }

  update() {
    this.counterTarget.textContent = this.count.toLocaleString()
    this.syncCounterState()
  }

  get count() {
    const currentLength = this.currentLength

    if (!(this.hasCountdownValue && this.countdownValue)) return currentLength

    if (this.maxLength < 0) {
      console.error(
        `[stimulus-character-counter] You need to add a maxlength attribute on the input to use countdown mode. The current value is: ${this.maxLength}.`
      )
    }

    return Math.max(this.maxLength - currentLength, 0)
  }

  get maxLength() {
    return this.hasMaxLengthValue ? this.maxLengthValue : this.inputTarget.maxLength
  }

  get currentLength() {
    if (!this.hasInputTarget) return 0

    if (this.inputTarget.tagName === "LEXXY-EDITOR") {
      return this.inputTarget.toString().length
    }

    return this.inputTarget.value?.length ?? 0
  }

  syncCounterState() {
    if (!this.hasCounterTarget) return

    const classList = this.counterTarget.classList
    classList.remove("text-content-muted", "text-warning-text", "text-danger-text")

    if (this.maxLength <= 0) {
      classList.add("text-content-muted")
      return
    }

    const percentage = this.currentLength / this.maxLength

    if (percentage >= this.dangerThresholdValue) {
      classList.add("text-danger-text")
    } else if (percentage >= this.warningThresholdValue) {
      classList.add("text-warning-text")
    } else {
      classList.add("text-content-muted")
    }
  }
}
