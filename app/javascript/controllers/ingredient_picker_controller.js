import { Controller } from "@hotwired/stimulus"

const LOADING_MESSAGES = [
  "Checking what's in your kitchen...",
  "Matching your ingredients to recipes...",
  "Picking the tastiest ideas...",
  "Writing up the steps..."
]

export default class extends Controller {
  static targets = ["input", "results", "chips", "submit", "label", "loading", "message", "empty", "status", "count"]
  static values = { options: Array, selected: Array }

  connect() {
    this.chosen = [...this.selectedValue]
    this.options = []
    this.activeIndex = -1

    // The form wraps this element, so listen for its submit event directly.
    this.form = this.element.closest("form")
    this.onSubmit = () => this.startLoading()
    this.onPageShow = (event) => { if (event.persisted) this.stopLoading() }
    this.onDocumentClick = (event) => { if (!this.element.contains(event.target)) this.closeResults() }

    this.form?.addEventListener("submit", this.onSubmit)
    window.addEventListener("pageshow", this.onPageShow)
    document.addEventListener("click", this.onDocumentClick)

    this.renderChips()
    document.getElementById("form-error")?.focus()
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.onSubmit)
    window.removeEventListener("pageshow", this.onPageShow)
    document.removeEventListener("click", this.onDocumentClick)
    clearInterval(this.timer)
  }

  startLoading() {
    this.submitTarget.disabled = true
    this.labelTarget.textContent = "Finding recipes..."
    this.loadingTarget.classList.remove("hidden")
    document.getElementById("results")?.classList.add("hidden")

    let index = 0
    this.messageTarget.textContent = LOADING_MESSAGES[0]
    clearInterval(this.timer)
    this.timer = setInterval(() => {
      index = (index + 1) % LOADING_MESSAGES.length
      this.messageTarget.textContent = LOADING_MESSAGES[index]
    }, 2500)
  }

  // Resets the page if the user comes back with the browser's Back button.
  stopLoading() {
    clearInterval(this.timer)
    this.loadingTarget.classList.add("hidden")
    document.getElementById("results")?.classList.remove("hidden")
    this.labelTarget.textContent = "Find recipes"
    this.renderChips()
  }

  search() {
    const typed = this.inputTarget.value.trim()
    const q = typed.toLowerCase()
    this.closeResults()

    if (q === "") return

    const matches = this.optionsValue
      .filter((name) => name.toLowerCase().includes(q) && !this.has(name))
      .slice(0, 8)
      .map((name) => ({ label: name, value: name }))

    const exact = matches.some((option) => option.value.toLowerCase() === q)
    if (!exact && !this.has(typed)) {
      matches.push({ label: `Add "${typed}"`, value: typed })
    }

    this.options = matches
    matches.forEach((option, index) => this.resultsTarget.appendChild(this.resultButton(option, index)))

    if (matches.length > 0) {
      this.resultsTarget.classList.remove("hidden")
      this.inputTarget.setAttribute("aria-expanded", "true")
    }
  }

  keydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (this.resultsTarget.classList.contains("hidden")) this.search()
        else this.setActive(this.activeIndex + 1)
        break
      case "ArrowUp":
        event.preventDefault()
        if (!this.resultsTarget.classList.contains("hidden")) this.setActive(this.activeIndex - 1)
        break
      case "Enter":
        event.preventDefault()
        if (!this.resultsTarget.classList.contains("hidden")) {
          const option = this.options[this.activeIndex >= 0 ? this.activeIndex : 0]
          if (option) this.add(option.value)
        }
        break
      case "Escape":
        event.preventDefault()
        this.closeResults()
        break
    }
  }

  setActive(index) {
    if (this.options.length === 0) return

    this.activeIndex = (index + this.options.length) % this.options.length
    const buttons = this.resultsTarget.querySelectorAll('[role="option"]')

    buttons.forEach((button, i) => {
      const active = i === this.activeIndex
      button.classList.toggle("bg-wood-100", active)
      button.setAttribute("aria-selected", String(active))
    })

    const activeButton = buttons[this.activeIndex]
    activeButton?.scrollIntoView({ block: "nearest" })
    this.inputTarget.setAttribute("aria-activedescendant", activeButton.id)
  }

  closeResults() {
    this.resultsTarget.replaceChildren()
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.options = []
    this.activeIndex = -1
  }

  add(name) {
    const clean = name.trim().slice(0, 40)
    if (clean === "" || this.has(clean)) return

    this.chosen.push(clean)
    this.inputTarget.value = ""
    this.closeResults()
    this.renderChips()
    this.announce(`Added ${clean}. ${this.chosen.length} selected.`)
    this.inputTarget.focus()
  }

  addSuggestion(event) {
    this.add(event.currentTarget.dataset.name || "")
  }

  remove(name) {
    this.chosen = this.chosen.filter((item) => item !== name)
    this.renderChips()
    this.announce(`Removed ${name}. ${this.chosen.length} selected.`)
  }

  has(name) {
    return this.chosen.some((item) => item.toLowerCase() === name.toLowerCase())
  }

  resultButton(option, index) {
    const button = document.createElement("button")
    button.type = "button"
    button.id = `ingredient-option-${index}`
    button.setAttribute("role", "option")
    button.setAttribute("aria-selected", "false")
    button.className = "block min-h-11 w-full rounded-lg px-3 py-2 text-left text-sm hover:bg-wood-100"
    button.textContent = option.label
    button.addEventListener("click", () => this.add(option.value))
    button.addEventListener("mousemove", () => this.setActive(index))
    return button
  }

  renderChips() {
    this.chipsTarget.replaceChildren()

    this.chosen.forEach((name) => {
      const chip = document.createElement("span")
      chip.className = "ingredient-chip"
      chip.append(document.createTextNode(name))

      const removeButton = document.createElement("button")
      removeButton.type = "button"
      removeButton.textContent = "×"
      removeButton.setAttribute("aria-label", `Remove ${name}`)
      removeButton.className = "chip-remove"
      removeButton.addEventListener("click", () => this.remove(name))
      chip.appendChild(removeButton)

      const hidden = document.createElement("input")
      hidden.type = "hidden"
      hidden.name = "ingredients[]"
      hidden.value = name
      chip.appendChild(hidden)

      this.chipsTarget.appendChild(chip)
    })

    const none = this.chosen.length === 0
    this.emptyTarget.classList.toggle("hidden", !none)
    this.countTarget.textContent = none ? "" : `(${this.chosen.length})`
    this.submitTarget.disabled = none
  }

  announce(message) {
    this.statusTarget.textContent = message
  }
}
