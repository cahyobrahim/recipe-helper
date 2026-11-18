import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "step", "counter", "prev", "next", "announcement"]
  static values = { steps: Array }

  connect() {
    this.index = 0
    this.onKeydown = (event) => this.handleKeydown(event)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  start() {
    this.index = 0
    this.render()
    this.panelTarget.classList.remove("hidden")
    document.addEventListener("keydown", this.onKeydown)
    this.nextTarget.focus()
  }

  next() {
    if (this.index < this.stepsValue.length - 1) this.index += 1
    this.render()
  }

  prev() {
    if (this.index > 0) this.index -= 1
    this.render()
  }

  finish() {
    this.panelTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.onKeydown)
  }

  handleKeydown(event) {
    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.prev()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.finish()
    }
  }

  render() {
    const total = this.stepsValue.length
    this.stepTarget.textContent = this.stepsValue[this.index]
    this.counterTarget.textContent = `Step ${this.index + 1} of ${total}`
    this.prevTarget.disabled = this.index === 0
    this.nextTarget.disabled = this.index === total - 1
    this.announcementTarget.textContent = this.counterTarget.textContent
  }
}
