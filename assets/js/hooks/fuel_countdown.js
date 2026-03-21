const FuelCountdown = {
  mounted() {
    this._interval = null
    this._renderCountdown()
  },

  updated() {
    this._renderCountdown()
  },

  destroyed() {
    this._clearInterval()
  },

  _renderCountdown() {
    this._clearInterval()

    const iso = this.el.dataset.depletesAt
    if (!iso) return

    const targetMs = Date.parse(iso)
    if (Number.isNaN(targetMs)) return

    const update = () => {
      const remainingSeconds = Math.max(Math.floor((targetMs - Date.now()) / 1000), 0)
      const hours = Math.floor(remainingSeconds / 3600)
      const minutes = Math.floor((remainingSeconds % 3600) / 60)
      const seconds = remainingSeconds % 60

      if (remainingSeconds === 0) {
        this.el.textContent = "Depleted"
        this._clearInterval()
        return
      }

      this.el.textContent = `in ${hours}h ${minutes}m ${seconds}s`
    }

    update()
    this._interval = window.setInterval(update, 1000)
  },

  _clearInterval() {
    if (this._interval) {
      window.clearInterval(this._interval)
      this._interval = null
    }
  }
}

export default FuelCountdown
