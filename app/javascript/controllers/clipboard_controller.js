import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flash("Copied!")
    } catch {
      this.flash("Copy failed — select the text instead")
    }
  }

  print() {
    window.print()
  }

  flash(message) {
    const button = this.element.querySelector('[data-action="click->clipboard#copy"]')
    if (!button) return

    const original = button.textContent
    button.textContent = message
    setTimeout(() => { button.textContent = original }, 1800)
  }
}
