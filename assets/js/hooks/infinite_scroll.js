const InfiniteScroll = {
  mounted() {
    this._loading = false
    this._observer = null
    this._observe()
  },

  updated() {
    this._loading = false
    this._observe()
  },

  destroyed() {
    this._disconnect()
  },

  _observe() {
    this._disconnect()

    if (!this._hasMore() || typeof IntersectionObserver !== "function") {
      return
    }

    this._observer = new IntersectionObserver((entries) => {
      if (this._loading || !this._hasMore()) {
        return
      }

      const isVisible = entries.some((entry) => entry.isIntersecting)

      if (isVisible) {
        this._loading = true
        this.pushEvent("load_more", {})
      }
    })

    this._observer.observe(this.el)
  },

  _disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
  },

  _hasMore() {
    return this.el.dataset.hasMore === "true"
  }
}

export default InfiniteScroll
