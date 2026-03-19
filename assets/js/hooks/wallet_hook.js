/**
 * WalletConnect LiveView Hook
 *
 * Discovers Sui Wallet Standard wallets (preferring EVE Vault),
 * connects, signs a server-provided challenge nonce via signPersonalMessage,
 * and submits the signed payload to POST /session via hidden form.
 *
 * Uses raw Wallet Standard browser events + @mysten/sui for Transaction building.
 */
import { Transaction } from "@mysten/sui/transactions"

const DISCOVERY_TIMEOUT_MS = 500

const WalletConnect = {
  mounted() {
    this.wallets = []
    this.selectedWallet = null
    this.currentAccount = null
    this.pendingAccounts = null
    this._onRegister = null
    this._discoveryTimer = null
    this._walletUnsubscribe = null
    this._pendingReportEffects = null

    this._startDiscovery()

    this.handleEvent("connect_wallet", ({ index }) => {
      this._connectWallet(index)
    })

    this.handleEvent("request_sign", ({ nonce, message }) => {
      this._signChallenge(nonce, message)
    })

    this.handleEvent("select_account", ({ index }) => {
      this._selectAccount(index)
    })

    this.handleEvent("request_sign_transaction", ({ tx_bytes }) => {
      this._signTransaction(tx_bytes)
    })

    this.handleEvent("report_transaction_effects", ({ effects }) => {
      this._reportTransactionEffects(effects)
    })
  },

  destroyed() {
    if (this._onRegister) {
      window.removeEventListener("wallet-standard:register-wallet", this._onRegister)
      this._onRegister = null
    }
    if (this._discoveryTimer) {
      clearTimeout(this._discoveryTimer)
      this._discoveryTimer = null
    }
    if (this._walletUnsubscribe) {
      this._walletUnsubscribe()
      this._walletUnsubscribe = null
    }
  },

  // -- Private --

  _startDiscovery() {
    // Wallet Standard register callback — wallets call this to register themselves
    const register = (...wallets) => {
      for (const wallet of wallets) {
        if (wallet && wallet.name && wallet.features) {
          this.wallets.push(wallet)
        }
      }

      // Re-push wallet list if discovery already finalized and no auth in progress
      if (!this._discoveryTimer && !this.selectedWallet) {
        this._pushWalletList()
      }
    }

    // Listen for wallet-standard:register-wallet events
    // Per spec, event.detail is a callback: ({ register }) => void
    this._onRegister = (event) => {
      try {
        if (typeof event.detail === "function") {
          event.detail({ register })
        }
      } catch (_e) {
        // Ignore malformed wallet registrations
      }
    }

    window.addEventListener("wallet-standard:register-wallet", this._onRegister)

    // Announce readiness — triggers already-registered wallets to re-fire
    // Per spec, detail must include { register } so wallets can call it
    try {
      window.dispatchEvent(
        new CustomEvent("wallet-standard:app-ready", { detail: { register } })
      )
    } catch (_e) {
      // Ignore if dispatch fails (e.g., restricted environment)
    }

    this._discoveryTimer = setTimeout(() => {
      this._discoveryTimer = null
      this._finalizeDiscovery()
    }, DISCOVERY_TIMEOUT_MS)
  },

  _finalizeDiscovery() {
    this._pushWalletList()
    // Auto-connect for transaction signing on non-dashboard pages
    if (this.el.id !== "wallet-connect" && this.wallets.length >= 1 && !this.selectedWallet) {
      this._silentConnect(0)
    }
  },

  _pushWalletList() {
    // Sort: EVE Vault first, then by discovery order
    this.wallets.sort((a, b) => {
      if (a.name === "Eve Vault") return -1
      if (b.name === "Eve Vault") return 1
      return 0
    })

    const walletPayloads = this.wallets.map((w) => ({
      name: w.name,
      icon: w.icon || ""
    }))

    this.pushEvent("wallet_detected", { wallets: walletPayloads })
  },

  async _connectWallet(index) {
    const wallet = this.wallets[index]
    if (!wallet) {
      this.pushEvent("wallet_error", { reason: "Selected wallet not available" })
      return
    }

    const connectFeature = wallet.features && wallet.features["standard:connect"]
    if (!connectFeature) {
      this.pushEvent("wallet_error", { reason: "Wallet does not support connection" })
      return
    }

    try {
      const result = await connectFeature.connect()
      const accounts = result.accounts || []
      if (accounts.length === 0) {
        this.pushEvent("wallet_error", { reason: "No accounts available in wallet" })
        return
      }

      this.selectedWallet = wallet

      // Subscribe to wallet events for disconnect and account change detection
      this._subscribeWalletEvents(wallet)

      if (accounts.length === 1) {
        // Single account — auto-select
        this.currentAccount = accounts[0]
        this.pushEvent("wallet_connected", {
          address: this.currentAccount.address,
          name: wallet.name
        })
      } else {
        // Multiple accounts — send list to server for account picker
        this.pendingAccounts = accounts
        this.pushEvent("wallet_accounts", {
          accounts: accounts.map(a => ({
            address: a.address,
            label: a.label || null
          }))
        })
      }
    } catch (err) {
      const message = err && err.message ? err.message : "Connection rejected"
      this.pushEvent("wallet_error", { reason: message })
    }
  },

  _selectAccount(index) {
    if (this.pendingAccounts && this.pendingAccounts[index]) {
      this.currentAccount = this.pendingAccounts[index]
      this.pushEvent("wallet_connected", {
        address: this.currentAccount.address,
        name: this.selectedWallet.name
      })
      this.pendingAccounts = null
    } else {
      this.pushEvent("wallet_error", { reason: "Selected account not available" })
    }
  },

  async _signChallenge(nonce, message) {
    if (!this.selectedWallet || !this.currentAccount) {
      this.pushEvent("wallet_error", { reason: "No wallet connected" })
      return
    }

    const signFeature =
      this.selectedWallet.features &&
      this.selectedWallet.features["sui:signPersonalMessage"]
    if (!signFeature) {
      this.pushEvent("wallet_error", {
        reason: "Wallet does not support message signing"
      })
      return
    }

    try {
      const messageBytes = new TextEncoder().encode(message)
      const result = await signFeature.signPersonalMessage({
        message: messageBytes,
        account: this.currentAccount
      })

      this._submitVerificationForm(
        this.currentAccount.address,
        result.bytes,
        result.signature,
        nonce
      )
    } catch (err) {
      const message =
        err && err.message ? err.message : "User rejected signing request"
      this.pushEvent("wallet_error", { reason: message })
    }
  },

  async _silentConnect(index) {
    const wallet = this.wallets[index]
    if (!wallet) return

    const connectFeature = wallet.features && wallet.features["standard:connect"]
    if (!connectFeature) return

    try {
      const result = await connectFeature.connect()
      const accounts = result.accounts || []
      if (accounts.length > 0) {
        this.selectedWallet = wallet
        this.currentAccount = accounts[0]

        // Subscribe to wallet events for disconnect/account change detection
        this._subscribeWalletEvents(wallet)
      }
    } catch (_e) {
      // Silent — signing will show an error if wallet isn't available
    }
  },

  _subscribeWalletEvents(wallet) {
    const eventsFeature = wallet.features && wallet.features["standard:events"]
    if (eventsFeature) {
      // Unsubscribe from previous wallet if any
      if (this._walletUnsubscribe) {
        this._walletUnsubscribe()
      }
      this._walletUnsubscribe = eventsFeature.on("change", ({ accounts: updated }) => {
        if (!updated || updated.length === 0) {
          this.pushEvent("wallet_error", { reason: "Wallet disconnected" })
          this.selectedWallet = null
          this.currentAccount = null
        } else if (this.currentAccount) {
          const stillPresent = updated.some(a => a.address === this.currentAccount.address)
          if (!stillPresent) {
            this.pushEvent("wallet_account_changed", {})
          }
        }
      })
    }
  },

  _reportTransactionEffects(effects) {
    if (this._pendingReportEffects) {
      this._pendingReportEffects(effects)
      this._pendingReportEffects = null
    }
  },

  async _signTransaction(txBytesBase64) {
    if (!this.selectedWallet || !this.currentAccount) {
      this.pushEvent("transaction_error", { reason: "No wallet connected" })
      return
    }

    const signFeature =
      this.selectedWallet.features &&
      this.selectedWallet.features["sui:signTransaction"]
    if (!signFeature) {
      this.pushEvent("transaction_error", {
        reason: "Wallet does not support transaction signing"
      })
      return
    }

    try {
      const raw = atob(txBytesBase64)
      const kindBytes = new Uint8Array(raw.length)
      for (let i = 0; i < raw.length; i++) {
        kindBytes[i] = raw.charCodeAt(i)
      }

      const transaction = Transaction.fromKind(kindBytes)
      transaction.setSender(this.currentAccount.address)

      const chain =
        this.el.dataset.suiChain ||
        (this.currentAccount.chains && this.currentAccount.chains[0]) ||
        "sui:testnet"
      const result = await signFeature.signTransaction({
        transaction,
        account: this.currentAccount,
        chain
      })

      // Store reportTransactionEffects callback if wallet provides one.
      // Server should call report_transaction_effects after execution
      // so the wallet can update its cached object versions.
      if (result.reportTransactionEffects) {
        this._pendingReportEffects = result.reportTransactionEffects
      }

      this.pushEvent("transaction_signed", {
        bytes: result.bytes,
        signature: result.signature
      })
    } catch (err) {
      const reason =
        err && err.message ? err.message : "User rejected transaction"
      this.pushEvent("transaction_error", { reason })
    }
  },

  _submitVerificationForm(address, bytes, signature, nonce) {
    const csrfMeta = document.querySelector("meta[name='csrf-token']")
    if (!csrfMeta) {
      this.pushEvent("wallet_error", {
        reason: "Session error — please refresh"
      })
      return
    }

    const form = document.createElement("form")
    form.method = "POST"
    form.action = "/session"
    form.style.display = "none"

    const fields = {
      _csrf_token: csrfMeta.getAttribute("content"),
      wallet_address: address,
      bytes: bytes,
      signature: signature,
      nonce: nonce
    }

    for (const [name, value] of Object.entries(fields)) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }

    document.body.appendChild(form)
    form.submit()
  }
}

export default WalletConnect
