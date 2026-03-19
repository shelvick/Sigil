/**
 * LiveView Hook Test Harness
 *
 * Simulates the Phoenix LiveView hook context (this.pushEvent, this.handleEvent,
 * this.el, etc.) so hooks can be mounted and tested without a real LiveView.
 *
 * Usage:
 *   import { mountHook } from "./support/liveview_hook"
 *   import WalletConnect from "../../hooks/wallet_hook"
 *
 *   const { hook, events, pushServerEvent, destroy } = mountHook(WalletConnect, {
 *     el: { id: "wallet-connect", dataset: {} }
 *   })
 */

/**
 * Mount a LiveView hook in a test context.
 *
 * @param {object} hookDef - The hook definition object (e.g., WalletConnect)
 * @param {object} opts
 * @param {object} opts.el - Mock DOM element (defaults to a div)
 * @param {object} opts.dataset - Shortcut to set el.dataset properties
 * @returns {{ hook, events, pushServerEvent, destroy }}
 */
export function mountHook(hookDef, opts = {}) {
  const events = []
  const handlers = {}

  const el = opts.el || document.createElement("div")
  if (opts.dataset) {
    Object.assign(el.dataset, opts.dataset)
  }
  if (opts.id) {
    el.id = opts.id
  }

  // Build the context object that LiveView provides as `this`
  const hook = Object.create(hookDef)

  hook.el = el

  hook.pushEvent = (event, payload) => {
    events.push({ event, payload })
  }

  hook.handleEvent = (event, callback) => {
    handlers[event] = callback
  }

  // Call mounted()
  hook.mounted()

  return {
    hook,
    events,

    /** Simulate a server-pushed event (like this.handleEvent receives) */
    pushServerEvent(event, payload) {
      const handler = handlers[event]
      if (!handler) {
        throw new Error(
          `No handler registered for "${event}". Registered: [${Object.keys(handlers).join(", ")}]`
        )
      }
      return handler(payload)
    },

    /** Check if a specific event was pushed to the server */
    findEvent(name) {
      return events.find((e) => e.event === name)
    },

    /** Get all events pushed to the server with a given name */
    findEvents(name) {
      return events.filter((e) => e.event === name)
    },

    /** Tear down the hook */
    destroy() {
      if (hook.destroyed) {
        hook.destroyed()
      }
    }
  }
}
