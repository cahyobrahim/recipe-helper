import { Controller } from "@hotwired/stimulus"

const MESSAGES = [
  "Checking what's in your kitchen…",
  "Matching your ingredients to recipes…",
  "Picking the tastiest ideas…",
  "Writing up the steps…"
]

export default class extends Controller {
  static targets = ["results", "announcer", "message"]
  static values = { url: String, interval: { type: Number, default: 2500 } }

  connect() {
    this.messageIndex = 0
    this.rotateMessages()
    this.timer = setTimeout(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearInterval(this.messageTimer)
  }

  rotateMessages() {
    if (!this.hasMessageTarget) return

    this.messageTimer = setInterval(() => {
      this.messageIndex = (this.messageIndex + 1) % MESSAGES.length
      this.messageTarget.textContent = MESSAGES[this.messageIndex]
    }, 2500)
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        cache: "no-store"
      })
      if (!response.ok) throw new Error(`Status ${response.status}`)

      const data = await response.json()
      if (data.state === "done" || data.state === "error") {
        this.finish(data)
        return
      }
    } catch {
      // A transient failure should not abandon a request that is still cooking.
    }

    this.timer = setTimeout(() => this.poll(), this.intervalValue)
  }

  finish(data) {
    clearInterval(this.messageTimer)

    if (typeof data.html === "string") this.resultsTarget.innerHTML = data.html

    this.announcerTarget.textContent = data.state === "done"
      ? "Recipes are ready."
      : "We couldn't finish generating recipes. Please try again."

    // Removing the controller attribute disconnects this instance and stops polling.
    this.element.removeAttribute("data-controller")
    this.element.removeAttribute("data-recipe-status-url-value")
  }
}
