import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { mountHook } from "./support/liveview_hook"
import { createMockWallet, registerWallet } from "./support/mock_wallet"
import WalletConnect from "../hooks/wallet_hook"

// Mock @mysten/sui Transaction for transaction signing tests
vi.mock("@mysten/sui/transactions", () => ({
  Transaction: {
    fromKind: vi.fn(() => ({
      setSender: vi.fn()
    }))
  }
}))

describe("WalletConnect hook", () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  describe("wallet discovery", () => {
    it("discovers wallets registered before mount via app-ready", () => {
      // Pre-register a wallet (simulates extension already loaded)
      let capturedRegister
      window.addEventListener(
        "wallet-standard:app-ready",
        (e) => {
          capturedRegister = e.detail.register
        },
        { once: true }
      )

      const { events, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      // Simulate a wallet responding to app-ready
      const wallet = createMockWallet({ name: "Eve Vault" })
      capturedRegister(wallet)

      // Advance past discovery timeout
      vi.advanceTimersByTime(600)

      const detected = events.find((e) => e.event === "wallet_detected")
      expect(detected).toBeDefined()
      expect(detected.payload.wallets).toHaveLength(1)
      expect(detected.payload.wallets[0].name).toBe("Eve Vault")

      destroy()
    })

    it("discovers wallets registered after mount via register-wallet event", () => {
      const { events, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      // Wallet registers after mount
      const wallet = createMockWallet({ name: "Sui Wallet" })
      registerWallet(wallet)

      vi.advanceTimersByTime(600)

      const detected = events.find((e) => e.event === "wallet_detected")
      expect(detected).toBeDefined()
      expect(detected.payload.wallets[0].name).toBe("Sui Wallet")

      destroy()
    })

    it("sorts Eve Vault to the front", () => {
      const { events, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(createMockWallet({ name: "Other Wallet" }))
      registerWallet(createMockWallet({ name: "Eve Vault" }))
      registerWallet(createMockWallet({ name: "Another Wallet" }))

      vi.advanceTimersByTime(600)

      const detected = events.find((e) => e.event === "wallet_detected")
      expect(detected.payload.wallets[0].name).toBe("Eve Vault")

      destroy()
    })
  })

  describe("wallet connection", () => {
    it("auto-selects single account and pushes wallet_connected", async () => {
      const wallet = createMockWallet({
        name: "Eve Vault",
        accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)

      // Server tells hook to connect wallet at index 0
      await pushServerEvent("connect_wallet", { index: 0 })

      const connected = events.find((e) => e.event === "wallet_connected")
      expect(connected).toBeDefined()
      expect(connected.payload.address).toBe("0xabc123")
      expect(connected.payload.name).toBe("Eve Vault")

      destroy()
    })

    it("presents account picker for multi-account wallets", async () => {
      const wallet = createMockWallet({
        accounts: [
          { address: "0xabc", chains: ["sui:testnet"], label: "Main" },
          { address: "0xdef", chains: ["sui:testnet"], label: "Alt" }
        ]
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)

      await pushServerEvent("connect_wallet", { index: 0 })

      const accounts = events.find((e) => e.event === "wallet_accounts")
      expect(accounts).toBeDefined()
      expect(accounts.payload.accounts).toHaveLength(2)
      expect(accounts.payload.accounts[0].label).toBe("Main")

      // No wallet_connected yet — waiting for account selection
      expect(events.find((e) => e.event === "wallet_connected")).toBeUndefined()

      destroy()
    })

    it("completes connection after account selection", async () => {
      const wallet = createMockWallet({
        accounts: [
          { address: "0xabc", chains: ["sui:testnet"] },
          { address: "0xdef", chains: ["sui:testnet"] }
        ]
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)

      await pushServerEvent("connect_wallet", { index: 0 })
      pushServerEvent("select_account", { index: 1 })

      const connected = events.find((e) => e.event === "wallet_connected")
      expect(connected).toBeDefined()
      expect(connected.payload.address).toBe("0xdef")

      destroy()
    })

    it("pushes error for invalid wallet index", async () => {
      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      vi.advanceTimersByTime(600)

      await pushServerEvent("connect_wallet", { index: 99 })

      const error = events.find((e) => e.event === "wallet_error")
      expect(error).toBeDefined()
      expect(error.payload.reason).toMatch(/not available/)

      destroy()
    })

    it("detects wallet disconnect after silent connect on non-dashboard pages", async () => {
      // BUG: _silentConnect doesn't subscribe to standard:events,
      // so wallet disconnect goes undetected on non-dashboard pages
      const wallet = createMockWallet({
        accounts: [{ address: "0xabc", chains: ["sui:testnet"] }]
      })

      // Mount on a NON-dashboard page — triggers _silentConnect
      const { events, destroy } = mountHook(WalletConnect, {
        id: "diplomacy-page"
      })

      registerWallet(wallet)
      // advanceTimersByTimeAsync flushes both timers and the microtask queue,
      // so _silentConnect's async connect() resolves before we continue
      await vi.advanceTimersByTimeAsync(600)

      // Wallet emits disconnect (user disconnected via wallet extension)
      wallet._emitChange({ accounts: [] })

      const error = events.find((e) => e.event === "wallet_error")
      expect(error).toBeDefined()
      expect(error.payload.reason).toMatch(/disconnected/i)

      destroy()
    })

    it("detects account change after silent connect on non-dashboard pages", async () => {
      const wallet = createMockWallet({
        accounts: [{ address: "0xabc", chains: ["sui:testnet"] }]
      })

      const { events, destroy } = mountHook(WalletConnect, {
        id: "diplomacy-page"
      })

      registerWallet(wallet)
      await vi.advanceTimersByTimeAsync(600)

      // Wallet emits account change (user switched to different account)
      wallet._emitChange({
        accounts: [{ address: "0xdifferent", chains: ["sui:testnet"] }]
      })

      const changed = events.find((e) => e.event === "wallet_account_changed")
      expect(changed).toBeDefined()

      destroy()
    })

    it("pushes error when wallet rejects connection", async () => {
      const wallet = createMockWallet({
        overrides: {
          connect: {
            connect: async () => {
              throw new Error("User rejected")
            }
          }
        }
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)

      await pushServerEvent("connect_wallet", { index: 0 })

      const error = events.find((e) => e.event === "wallet_error")
      expect(error).toBeDefined()
      expect(error.payload.reason).toBe("User rejected")

      destroy()
    })
  })

  describe("message signing", () => {
    it("signs challenge and submits verification form", async () => {
      const wallet = createMockWallet({
        accounts: [{ address: "0xabc", chains: ["sui:testnet"] }]
      })

      const { pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      // Set up CSRF meta tag
      const meta = document.createElement("meta")
      meta.name = "csrf-token"
      meta.content = "test-csrf"
      document.head.appendChild(meta)

      registerWallet(wallet)
      vi.advanceTimersByTime(600)

      await pushServerEvent("connect_wallet", { index: 0 })

      // Spy on form submission
      const submitSpy = vi.fn()
      vi.spyOn(document.body, "appendChild").mockImplementation((el) => {
        if (el.tagName === "FORM") {
          el.submit = submitSpy
          // Actually append so querySelector works
          document.body.append(el)
        }
      })

      await pushServerEvent("request_sign", {
        nonce: "test-nonce",
        message: "Sign this challenge"
      })

      expect(wallet._calls.signPersonalMessage).toHaveLength(1)
      expect(submitSpy).toHaveBeenCalled()

      // Verify form fields
      const form = document.querySelector("form[action='/session']")
      expect(form).toBeDefined()
      expect(form.querySelector("input[name='wallet_address']").value).toBe(
        "0xabc"
      )
      expect(form.querySelector("input[name='nonce']").value).toBe(
        "test-nonce"
      )

      // Cleanup
      document.head.removeChild(meta)
      document.querySelectorAll("form").forEach((f) => f.remove())
      vi.restoreAllMocks()
      destroy()
    })

    it("pushes error when no wallet connected", async () => {
      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      vi.advanceTimersByTime(600)

      await pushServerEvent("request_sign", {
        nonce: "n",
        message: "m"
      })

      const error = events.find((e) => e.event === "wallet_error")
      expect(error).toBeDefined()
      expect(error.payload.reason).toMatch(/No wallet connected/)

      destroy()
    })
  })

  describe("transaction signing", () => {
    it("signs transaction and pushes transaction_signed", async () => {
      const wallet = createMockWallet({
        accounts: [{ address: "0xabc", chains: ["sui:testnet"] }]
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)
      await pushServerEvent("connect_wallet", { index: 0 })

      // Server sends base64-encoded TransactionKind bytes
      // "dGVzdA==" is base64 for "test"
      await pushServerEvent("request_sign_transaction", {
        tx_bytes: "dGVzdA=="
      })

      const signed = events.find((e) => e.event === "transaction_signed")
      expect(signed).toBeDefined()
      expect(signed.payload.bytes).toBeDefined()
      expect(signed.payload.signature).toBeDefined()
      expect(wallet._calls.signTransaction).toHaveLength(1)

      destroy()
    })

    it("pushes error when no wallet connected for transaction signing", async () => {
      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      vi.advanceTimersByTime(600)

      await pushServerEvent("request_sign_transaction", {
        tx_bytes: "dGVzdA=="
      })

      const error = events.find((e) => e.event === "transaction_error")
      expect(error).toBeDefined()
      expect(error.payload.reason).toMatch(/No wallet connected/)

      destroy()
    })

    it("pushes error when wallet lacks signTransaction feature", async () => {
      const wallet = createMockWallet({
        accounts: [{ address: "0xabc", chains: ["sui:testnet"] }],
        disableFeatures: ["sui:signTransaction"]
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)
      await pushServerEvent("connect_wallet", { index: 0 })

      await pushServerEvent("request_sign_transaction", {
        tx_bytes: "dGVzdA=="
      })

      const error = events.find((e) => e.event === "transaction_error")
      expect(error).toBeDefined()
      expect(error.payload.reason).toMatch(/does not support/)

      destroy()
    })

    it("reports transaction effects back to wallet", async () => {
      // BUG: After server executes a signed tx, the wallet never learns
      // about the effects. This causes stale object versions on rapid txs.
      const reportEffectsSpy = vi.fn()
      const wallet = createMockWallet({
        accounts: [{ address: "0xabc", chains: ["sui:testnet"] }],
        overrides: {
          signTransaction: {
            signTransaction: async ({ transaction, account, chain }) => {
              wallet._calls.signTransaction.push({ transaction, account, chain })
              return {
                bytes: "dGVzdC10eC1ieXRlcw==",
                signature: "dGVzdC10eC1zaWduYXR1cmU=",
                // Wallet provides this callback for the dApp to report effects
                reportTransactionEffects: reportEffectsSpy
              }
            }
          }
        }
      })

      const { events, pushServerEvent, destroy } = mountHook(WalletConnect, {
        id: "diplomacy-page"
      })

      registerWallet(wallet)
      vi.advanceTimersByTime(600)
      await pushServerEvent("connect_wallet", { index: 0 })

      await pushServerEvent("request_sign_transaction", {
        tx_bytes: "dGVzdA=="
      })

      // Server executed the tx and sends back the raw effects
      pushServerEvent("report_transaction_effects", {
        effects: "base64-encoded-effects-bcs"
      })

      expect(reportEffectsSpy).toHaveBeenCalledWith("base64-encoded-effects-bcs")

      destroy()
    })
  })

  describe("cleanup", () => {
    it("removes event listeners on destroy", () => {
      const removeSpy = vi.spyOn(window, "removeEventListener")

      const { destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      destroy()

      expect(removeSpy).toHaveBeenCalledWith(
        "wallet-standard:register-wallet",
        expect.any(Function)
      )

      vi.restoreAllMocks()
    })

    it("clears discovery timer on destroy", () => {
      const { destroy } = mountHook(WalletConnect, {
        id: "wallet-connect"
      })

      // Destroy before timer fires
      destroy()

      // Advancing timers should not cause errors
      vi.advanceTimersByTime(600)
    })
  })
})
