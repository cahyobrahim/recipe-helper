import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "ingredients", "announcement"]
  static values = {
    name: String,
    time: String,
    servings: Number,
    ingredients: Array,
    missing: Array,
    steps: Array
  }

  connect() {
    this.currentServings = this.servingsValue
    if (this.hasSelectTarget && this.hasIngredientsTarget) this.render()
  }

  change() {
    this.currentServings = Number(this.selectTarget.value) || this.servingsValue
    this.render()
  }

  render() {
    if (!this.hasIngredientsTarget) return

    const base = this.servingsValue || 1
    const multiplier = this.currentServings / base

    this.ingredientsTarget.replaceChildren(
      ...this.ingredientsValue.map((ingredient) => {
        const row = document.createElement("li")
        row.className = "flex gap-2"

        const amount = document.createElement("span")
        amount.className = "w-20 shrink-0 font-semibold text-wood-900"
        amount.textContent = this.formatAmount(Number(ingredient.quantity) * multiplier, ingredient.unit)

        const name = document.createElement("span")
        name.textContent = ingredient.name

        row.append(amount, name)
        return row
      })
    )

    const clipboard = this.application.getControllerForElementAndIdentifier(this.element, "clipboard")
    if (clipboard) clipboard.textValue = this.plainText()

    if (this.hasAnnouncementTarget) {
      this.announcementTarget.textContent = `Ingredients updated for ${this.currentServings} servings`
    }
  }

  plainText() {
    const lines = [ this.nameValue ]
    if (this.timeValue) lines.push(`Time: ${this.timeValue}`)
    lines.push(`Servings: ${this.currentServings}`)
    lines.push("", "Ingredients:")

    this.ingredientsValue.forEach((ingredient) => {
      const amount = this.formatAmount(Number(ingredient.quantity) * (this.currentServings / (this.servingsValue || 1)), ingredient.unit)
      lines.push(`- ${amount} ${ingredient.name}`.trim())
    })

    if (this.missingValue.length) lines.push("", `Optional extras: ${this.missingValue.join(", ")}`)
    lines.push("")
    this.stepsValue.forEach((step, index) => lines.push(`${index + 1}. ${step}`))
    return lines.join("\n")
  }

  formatAmount(quantity, unit) {
    const unitText = (unit || "").trim()
    if (unitText.toLowerCase().includes("taste")) return unitText || "to taste"

    const value = Number(quantity)
    if (!Number.isFinite(value) || value <= 0) return ""

    if (["g", "ml", "kg", "l", "oz", "lb"].includes(unitText.toLowerCase())) {
      return `${Math.max(1, Math.round(value))} ${unitText}`.trim()
    }

    const whole = Math.floor(value + 1e-9)
    const fraction = value - whole
    const glyphs = [[0.25, "¼"], [0.33, "⅓"], [0.5, "½"], [0.67, "⅔"], [0.75, "¾"]]
    let fractionText = ""
    let bestDifference = Infinity

    glyphs.forEach(([candidate, glyph]) => {
      const difference = Math.abs(fraction - candidate)
      if (difference < bestDifference) {
        bestDifference = difference
        fractionText = glyph
      }
    })

    if (bestDifference > 0.06) {
      fractionText = fraction >= 0.1 ? String(Math.round(fraction * 100) / 100) : ""
    }

    const number = whole > 0
      ? `${whole}${fractionText}`
      : (fractionText || String(Math.round(value * 100) / 100))

    return `${number} ${unitText}`.trim()
  }
}
