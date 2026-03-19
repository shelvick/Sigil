/**
 * Mock Wallet for Testing
 *
 * Implements the Wallet Standard interface used by wallet_hook.js.
 * Returns controllable responses without real cryptography.
 *
 * Usage:
 *   import { createMockWallet, registerWallet } from "./support/mock_wallet"
 *
 *   const wallet = createMockWallet({ name: "Eve Vault" })
 *   registerWallet(wallet)  // fires the browser event
 */

/**
 * Create a mock wallet implementing the Wallet Standard interface.
 *
 * @param {object} opts
 * @param {string} opts.name - Wallet name (default: "Test Wallet")
 * @param {string} opts.icon - Wallet icon URL (default: "")
 * @param {string[]} opts.chains - Supported chains (default: ["sui:testnet"])
 * @param {object[]} opts.accounts - Accounts to return on connect
 * @param {object} opts.overrides - Override specific feature implementations
 * @returns {object} A Wallet Standard compatible wallet object
 */
export function createMockWallet(opts = {}) {
  const accounts = opts.accounts || [
    { address: "0x" + "a1".repeat(32), chains: ["sui:testnet"], label: null }
  ]

  const eventListeners = []

  const wallet = {
    name: opts.name || "Test Wallet",
    icon: opts.icon || "",
    chains: opts.chains || ["sui:testnet"],

    // Track calls for assertions
    _calls: {
      connect: [],
      signPersonalMessage: [],
      signTransaction: []
    },

    // Programmatically trigger wallet events (disconnect, account change)
    _emitChange(change) {
      for (const listener of eventListeners) {
        listener(change)
      }
    },

    features: {
      "standard:connect": {
        connect: async () => {
          wallet._calls.connect.push({ timestamp: Date.now() })
          return { accounts }
        },
        ...(opts.overrides?.connect || {})
      },

      "standard:events": {
        on(event, listener) {
          eventListeners.push(listener)
          return () => {
            const idx = eventListeners.indexOf(listener)
            if (idx >= 0) eventListeners.splice(idx, 1)
          }
        }
      },

      "sui:signPersonalMessage": {
        signPersonalMessage: async ({ message, account }) => {
          wallet._calls.signPersonalMessage.push({ message, account })
          return {
            bytes: "dGVzdC1zaWduZWQtYnl0ZXM=",
            signature: "dGVzdC1zaWduYXR1cmU="
          }
        },
        ...(opts.overrides?.signPersonalMessage || {})
      },

      "sui:signTransaction": {
        signTransaction: async ({ transaction, account, chain }) => {
          wallet._calls.signTransaction.push({ transaction, account, chain })
          return {
            bytes: "dGVzdC10eC1ieXRlcw==",
            signature: "dGVzdC10eC1zaWduYXR1cmU="
          }
        },
        ...(opts.overrides?.signTransaction || {})
      }
    }
  }

  // Allow disabling specific features
  if (opts.disableFeatures) {
    for (const feature of opts.disableFeatures) {
      delete wallet.features[feature]
    }
  }

  return wallet
}

/**
 * Register a mock wallet via the Wallet Standard browser event.
 * This is what real wallet extensions do to announce themselves.
 */
export function registerWallet(wallet) {
  window.dispatchEvent(
    new CustomEvent("wallet-standard:register-wallet", {
      detail: ({ register }) => {
        register(wallet)
      }
    })
  )
}

/**
 * Create and immediately register a mock wallet.
 * Convenience for tests that just need a wallet available.
 */
export function setupMockWallet(opts = {}) {
  const wallet = createMockWallet(opts)
  registerWallet(wallet)
  return wallet
}
