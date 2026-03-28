import { decodeSuiPrivateKey } from "@mysten/sui/cryptography"
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519"

import {
  activatePseudonym,
  cachePseudonym,
  clearPseudonyms,
  getPseudonym,
  setActivePseudonym
} from "./pseudonym_store"

const DETERMINISTIC_MESSAGE = new TextEncoder().encode("Sigil pseudonym key v1")
const IV_LENGTH = 12

const PseudonymKey = {
  mounted() {
    this.wallets = []
    this.selectedWallet = null
    this.currentAccount = null
    this._onRegister = (event) => {
      try {
        if (typeof event.detail === "function") {
          event.detail({ register: (...wallets) => this._storeWallets(wallets) })
        }
      } catch (_error) {
        // Ignore malformed wallet registrations.
      }
    }

    window.addEventListener("wallet-standard:register-wallet", this._onRegister)
    this._announceWalletReady()

    this.handleEvent("create_pseudonym", async () => {
      await this._createPseudonym()
    })

    this.handleEvent("load_pseudonyms", async (payload) => {
      await this._loadPseudonyms(payload)
    })

    this.handleEvent("activate_pseudonym", async (payload) => {
      await this._activatePseudonym(payload)
    })

    this.handleEvent("sign_pseudonym_tx", async (payload) => {
      await this._signPseudonymTx(payload)
    })
  },

  destroyed() {
    if (this._onRegister) {
      window.removeEventListener("wallet-standard:register-wallet", this._onRegister)
      this._onRegister = null
    }
  },

  async _createPseudonym() {
    try {
      const { wallet, account } = await this._resolveWalletAccount()
      const encryptionKey = await this._deriveEncryptionKey(wallet, account)
      const keypair = Ed25519Keypair.generate()
      const address = keypair.getPublicKey().toSuiAddress()
      const secretKey = decodeSuiPrivateKey(keypair.getSecretKey()).secretKey
      const encrypted = await this._encryptSecretKey(secretKey, encryptionKey)

      cachePseudonym(address, keypair)
      setActivePseudonym(keypair)

      this.pushEvent("pseudonym_created", {
        pseudonym_address: address,
        encrypted_private_key: encrypted
      })
    } catch (error) {
      this._pushError(error?.message || "no_wallet", "encrypt")
    }
  },

  async _loadPseudonyms(payload) {
    const encryptedKeys = payload?.encrypted_keys || []

    if (encryptedKeys.length === 0) {
      clearPseudonyms()
      this.pushEvent("pseudonyms_loaded", { addresses: [], active_address: null })
      return
    }

    try {
      const { wallet, account } = await this._resolveWalletAccount()
      const encryptionKey = await this._deriveEncryptionKey(wallet, account)
      clearPseudonyms()

      const loadedAddresses = []

      for (const entry of encryptedKeys) {
        try {
          const secretKey = await this._decryptSecretKey(entry.encrypted_key, encryptionKey)
          const keypair = Ed25519Keypair.fromSecretKey(secretKey)
          cachePseudonym(entry.address, keypair)
          loadedAddresses.push(entry.address)
        } catch (_error) {
          // Skip corrupted blobs while preserving decryptable identities.
        }
      }

      if (loadedAddresses.length === 0) {
        throw new Error("decrypt_failed")
      }

      const requestedAddress = payload?.active_address
      const activeAddress =
        requestedAddress && getPseudonym(requestedAddress)
          ? requestedAddress
          : loadedAddresses[0]

      const activeKeypair = activatePseudonym(activeAddress)
      if (activeKeypair) {
        setActivePseudonym(activeKeypair)
      }

      this.pushEvent("pseudonyms_loaded", {
        addresses: loadedAddresses,
        active_address: activeAddress
      })
    } catch (error) {
      this._pushError(error?.message || "decrypt_failed", "load")
    }
  },

  async _activatePseudonym(payload) {
    const address = payload?.pseudonym_address
    const keypair = address ? getPseudonym(address) : null

    if (!keypair) {
      this._pushError("keypair_not_found", "activate")
      return
    }

    setActivePseudonym(keypair)
    this.pushEvent("pseudonym_activated", { pseudonym_address: address })
  },

  async _signPseudonymTx(payload) {
    const address = payload?.pseudonym_address
    const keypair = address ? getPseudonym(address) : null

    if (!keypair) {
      this._pushError("keypair_not_found", "sign")
      return
    }

    const txBytes = this._base64ToBytes(payload.tx_bytes)
    const result = await keypair.signTransaction(txBytes)
    this.pushEvent("pseudonym_tx_signed", { signature: result.signature })
  },

  async _resolveWalletAccount() {
    const targetAddress = this.el.dataset.address
    if (!targetAddress) {
      throw new Error("no_wallet")
    }

    const normalizedTarget = targetAddress.toLowerCase()
    this._announceWalletReady()

    for (const wallet of this.wallets) {
      const connectedAccount = (wallet.accounts || []).find(
        (candidate) => candidate.address?.toLowerCase() === normalizedTarget
      )

      if (connectedAccount) {
        this.selectedWallet = wallet
        this.currentAccount = connectedAccount
        return { wallet, account: connectedAccount }
      }

      const connectFeature = wallet.features?.["standard:connect"]
      if (!connectFeature) {
        continue
      }

      const result = await connectFeature.connect()
      const accounts = result.accounts || wallet.accounts || []
      const account = accounts.find((candidate) => candidate.address?.toLowerCase() === normalizedTarget)

      if (account) {
        wallet.accounts = accounts
        this.selectedWallet = wallet
        this.currentAccount = account
        return { wallet, account }
      }
    }

    throw new Error("no_wallet")
  },

  async _deriveEncryptionKey(wallet, account) {
    const signFeature = wallet.features?.["sui:signPersonalMessage"]
    if (!signFeature) {
      throw new Error("no_wallet")
    }

    try {
      const signed = await signFeature.signPersonalMessage({
        message: DETERMINISTIC_MESSAGE,
        account
      })

      const signatureBytes = new TextEncoder().encode(signed.signature)
      return new Uint8Array(await crypto.subtle.digest("SHA-256", signatureBytes))
    } catch (_error) {
      throw new Error("user_rejected")
    }
  },

  async _encryptSecretKey(secretKey, encryptionKey) {
    const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH))
    const key = await crypto.subtle.importKey("raw", encryptionKey, { name: "AES-GCM" }, false, ["encrypt"])
    const ciphertext = new Uint8Array(
      await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, secretKey)
    )

    return this._bytesToBase64(this._concatBytes(iv, ciphertext))
  },

  async _decryptSecretKey(encodedBlob, encryptionKey) {
    const blob = this._base64ToBytes(encodedBlob)
    if (blob.length <= IV_LENGTH + 16) {
      throw new Error("decrypt_failed")
    }

    const iv = blob.slice(0, IV_LENGTH)
    const ciphertext = blob.slice(IV_LENGTH)
    const key = await crypto.subtle.importKey("raw", encryptionKey, { name: "AES-GCM" }, false, ["decrypt"])

    try {
      return new Uint8Array(
        await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext)
      )
    } catch (_error) {
      throw new Error("decrypt_failed")
    }
  },

  _bytesToBase64(bytes) {
    return btoa(String.fromCharCode(...bytes))
  },

  _base64ToBytes(encoded) {
    const raw = atob(encoded)
    return Uint8Array.from(raw, (char) => char.charCodeAt(0))
  },

  _concatBytes(first, second) {
    const merged = new Uint8Array(first.length + second.length)
    merged.set(first, 0)
    merged.set(second, first.length)
    return merged
  },

  _storeWallets(wallets) {
    for (const wallet of wallets) {
      if (!wallet || !wallet.name || !wallet.features) {
        continue
      }

      if (!this.wallets.includes(wallet)) {
        this.wallets.push(wallet)
      }
    }
  },

  _announceWalletReady() {
    try {
      window.dispatchEvent(
        new CustomEvent("wallet-standard:app-ready", {
          detail: { register: (...wallets) => this._storeWallets(wallets) }
        })
      )
    } catch (_error) {
      // Ignore browsers that block custom event dispatch here.
    }
  },

  _pushError(reason, phase) {
    this.pushEvent("pseudonym_error", { reason, phase })
  }
}

export default PseudonymKey
