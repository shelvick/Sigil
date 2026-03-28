import { SealClient, SessionKey } from "@mysten/seal"
import { SuiJsonRpcClient } from "@mysten/sui/jsonRpc"
import { Transaction } from "@mysten/sui/transactions"

import { getActivePseudonym } from "./pseudonym_store"

const DEFAULT_SESSION_TTL_MIN = 10
const UNPUBLISHED_PACKAGE_ID = `0x${"0".repeat(64)}`

const SealEncrypt = {
  mounted() {
    this.wallets = []
    this.selectedWallet = null
    this.currentAccount = null
    this._cachedClients = null
    this._registerWallet = ({ register }) => {
      register((...wallets) => this._storeWallets(wallets))
    }
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

    this.handleEvent("encrypt_and_upload", async (payload) => {
      await this._encryptAndUpload(payload)
    })

    this.handleEvent("decrypt_intel", async (payload) => {
      await this._decryptIntel(payload)
    })
  },

  destroyed() {
    if (this._onRegister) {
      window.removeEventListener("wallet-standard:register-wallet", this._onRegister)
      this._onRegister = null
    }
  },

  async _encryptAndUpload(payload) {
    let phase = "init"

    try {
      const config = this._readConfig(payload)
      const { sealClient } = this._ensureClients(config)
      const sealId = payload?.seal_id || this._randomSealId()
      const intelPayload = this._buildIntelPayload(payload)

      this.pushEvent("seal_status", { status: "encrypting" })
      phase = "encrypt"

      const { encryptedObject } = await sealClient.encrypt({
        threshold: config.threshold,
        packageId: config.seal_package_id,
        id: sealId,
        data: new TextEncoder().encode(JSON.stringify(intelPayload))
      })

      this.pushEvent("seal_status", { status: "uploading" })
      phase = "upload"

      const encryptedBlobId = await this._uploadBlob(config, encryptedObject)

      this.pushEvent("seal_upload_complete", {
        seal_id: sealId,
        blob_id: encryptedBlobId
      })
    } catch (error) {
      this._pushSealError(error, phase)
    }
  },

  async _decryptIntel(payload) {
    let phase = "init"

    try {
      const config = this._readConfig(payload)
      const encryptedBlobId = payload.encrypted_blob_id || payload.blob_id
      const listingId = payload.listing_id
      const sealId = payload.seal_id
      const { sealClient, suiClient } = this._ensureClients(config)

      if (!encryptedBlobId) {
        throw new Error("Encrypted blob ID is missing")
      }
      if (!listingId) {
        throw new Error("Listing ID is missing")
      }
      if (!sealId) {
        throw new Error("Seal ID is missing")
      }
      if (!this.el.dataset.address) {
        throw new Error("Wallet address is missing")
      }

      this.pushEvent("seal_status", { status: "fetching" })
      phase = "fetch"
      const encryptedBytes = await this._fetchBlob(config, encryptedBlobId)

      this.pushEvent("seal_status", { status: "decrypting" })
      phase = "decrypt"

      const walletAddress = this.el.dataset.address.toLowerCase()
      const sellerAddress = (payload?.seller_address || this.el.dataset.activePseudonym || "")
        .toLowerCase()
      const activePseudonym = getActivePseudonym()
      const pseudonymAddress = activePseudonym?.getPublicKey?.()?.toSuiAddress?.()?.toLowerCase?.()

      let approvalSignerAddress = this.el.dataset.address
      let sessionKey

      if (activePseudonym && sellerAddress !== "" && pseudonymAddress === sellerAddress) {
        if (this.wallets.length === 0 && typeof activePseudonym.signTransaction === "function") {
          await activePseudonym.signTransaction(new Uint8Array([0]))
        }

        approvalSignerAddress = sellerAddress

        sessionKey = await SessionKey.create({
          address: sellerAddress,
          signer: activePseudonym,
          packageId: config.seal_package_id,
          ttlMin: DEFAULT_SESSION_TTL_MIN,
          suiClient
        })
      } else {
        const { wallet, account } = await this._resolveWalletAccount()
        approvalSignerAddress = account.address

        sessionKey = await SessionKey.create({
          address: account.address,
          packageId: config.seal_package_id,
          ttlMin: DEFAULT_SESSION_TTL_MIN,
          suiClient
        })

        const signFeature = wallet.features?.["sui:signPersonalMessage"]
        if (!signFeature) {
          throw new Error("Wallet does not support message signing")
        }

        const signed = await signFeature.signPersonalMessage({
          message: sessionKey.getPersonalMessage(),
          account
        })
        await sessionKey.setPersonalMessageSignature(signed.signature)
      }

      const txBytes = await this._buildApprovalTransaction({
        packageId: config.seal_package_id,
        listingId,
        sealId,
        suiClient,
        sender: approvalSignerAddress || walletAddress
      })

      const plaintextBytes = await sealClient.decrypt({
        data: encryptedBytes,
        sessionKey,
        txBytes
      })

      const decryptedJson = new TextDecoder().decode(plaintextBytes)
      this.pushEvent("seal_decrypt_complete", { data: decryptedJson })
    } catch (error) {
      this._pushSealError(error, phase)
    }
  },

  _ensureClients(config) {
    const cacheKey = JSON.stringify(config)
    if (this._cachedClients && this._cachedClients.key === cacheKey) {
      return this._cachedClients.value
    }

    const suiClient = new SuiJsonRpcClient({
      url: config.sui_rpc_url,
      network: this._networkName()
    })

    const sealClient = new SealClient({
      suiClient,
      serverConfigs: this._serverConfigs(config),
      verifyKeyServers: true,
      timeout: 10_000
    })

    this._cachedClients = {
      key: cacheKey,
      value: { suiClient, sealClient }
    }

    return this._cachedClients.value
  },

  _readConfig(payload) {
    const rawConfig = payload?.config || this.el.dataset.config
    const config = typeof rawConfig === "string" ? JSON.parse(rawConfig) : rawConfig

    if (!config || typeof config !== "object") {
      throw new Error("Seal config is missing")
    }

    if (!config.seal_package_id || config.seal_package_id === UNPUBLISHED_PACKAGE_ID) {
      throw new Error("Seal package is not deployed for this environment")
    }

    if (!Array.isArray(config.key_server_object_ids) || config.key_server_object_ids.length === 0) {
      throw new Error("Seal key servers are not configured")
    }

    if (!config.walrus_publisher_url || !config.walrus_aggregator_url || !config.sui_rpc_url) {
      throw new Error("Seal transport endpoints are incomplete")
    }

    return config
  },

  _buildIntelPayload(payload) {
    const intelData = payload?.intel_data || payload || {}

    return Object.fromEntries(
      Object.entries({
        report_type: intelData.report_type,
        solar_system_id: intelData.solar_system_id,
        assembly_id: intelData.assembly_id,
        notes: intelData.notes,
        label: intelData.label
      }).filter(([, value]) => value !== null && value !== undefined && value !== "")
    )
  },

  async _uploadBlob(config, encryptedObject) {
    const response = await fetch(
      `${config.walrus_publisher_url}/v1/blobs?epochs=${encodeURIComponent(config.walrus_epochs)}`,
      {
        method: "PUT",
        body: encryptedObject,
        headers: {
          "content-type": "application/octet-stream"
        }
      }
    )

    if (!response.ok) {
      throw new Error(`Walrus upload failed with status ${response.status}`)
    }

    const body = await response.json()
    const blobId =
      body?.newlyCreated?.blobObject?.blobId || body?.alreadyCertified?.blobId || null

    if (!blobId) {
      throw new Error("Walrus upload response did not include a blob ID")
    }

    return blobId
  },

  async _fetchBlob(config, encryptedBlobId) {
    const response = await fetch(
      `${config.walrus_aggregator_url}/v1/blobs/${encodeURIComponent(encryptedBlobId)}`
    )

    if (!response.ok) {
      throw new Error(`Walrus fetch failed with status ${response.status}`)
    }

    return new Uint8Array(await response.arrayBuffer())
  },

  async _buildApprovalTransaction({ packageId, listingId, sealId, suiClient, sender }) {
    const tx = new Transaction()
    tx.setSenderIfNotSet(sender)
    tx.moveCall({
      target: `${packageId}::seal_policy::seal_approve`,
      arguments: [tx.pure.vector("u8", Array.from(this._hexToBytes(sealId))), tx.object(listingId)]
    })

    return tx.build({ client: suiClient, onlyTransactionKind: true })
  },

  async _resolveWalletAccount() {
    const targetAddress = this.el.dataset.address
    if (!targetAddress) {
      throw new Error("Wallet address is missing")
    }

    const normalizedTarget = targetAddress.toLowerCase()

    if (this.currentAccount?.address?.toLowerCase() === normalizedTarget && this.selectedWallet) {
      return { wallet: this.selectedWallet, account: this.currentAccount }
    }

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

    throw new Error("Connected wallet account is unavailable")
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

  _serverConfigs(config) {
    return config.key_server_object_ids.map((entry) => {
      if (typeof entry === "string") {
        return { objectId: entry, weight: 1 }
      }

      return {
        weight: 1,
        ...entry
      }
    })
  },

  _networkName() {
    const chain = this.el.dataset.suiChain || "sui:testnet"
    return chain.replace(/^sui:/, "")
  },

  _randomSealId() {
    const bytes = crypto.getRandomValues(new Uint8Array(32))
    return `0x${Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")}`
  },

  _hexToBytes(hex) {
    const normalized = hex.startsWith("0x") ? hex.slice(2) : hex
    if (normalized.length % 2 !== 0) {
      throw new Error("Seal ID must be even-length hex")
    }

    const bytes = new Uint8Array(normalized.length / 2)
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Number.parseInt(normalized.slice(index * 2, index * 2 + 2), 16)
    }

    return bytes
  },

  _pushSealError(error, phase) {
    const reason = error instanceof Error ? error.message : String(error)
    this.pushEvent("seal_error", { reason, phase })
  }
}

export default SealEncrypt
