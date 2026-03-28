import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { mountHook } from "./support/liveview_hook"
import { createMockWallet, registerWallet } from "./support/mock_wallet"

const deterministicMessage = new TextEncoder().encode("Sigil pseudonym key v1")

async function loadHook() {
  const module = await import("../hooks/pseudonym_hook")
  return module.default
}

async function loadStore() {
  return import("../hooks/pseudonym_store")
}

async function activePseudonymAddress() {
  const store = await loadStore()
  const active = store.getActivePseudonym()

  if (!active) {
    return null
  }

  return active.getPublicKey().toSuiAddress()
}

async function clearPseudonyms() {
  try {
    const store = await loadStore()
    store.clearPseudonyms()
  } catch {
    // The tests should still fail on the missing hook module in TEST phase.
  }
}

function pseudonymHookDataset(address = "0xabc123") {
  return {
    address,
    suiChain: "sui:testnet"
  }
}

async function createEncryptedPseudonym(walletAddress, opts = {}) {
  const wallet =
    opts.wallet ||
    createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

  const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
    id: "pseudonym-key",
    dataset: pseudonymHookDataset(walletAddress)
  })

  registerWallet(wallet)
  await pushServerEvent("create_pseudonym", {})

  const created = events.find((event) => event.event === "pseudonym_created")

  destroy()

  return {
    wallet,
    created
  }
}

describe("PseudonymKey hook", () => {
  beforeEach(async () => {
    vi.resetModules()
    vi.clearAllMocks()
    await clearPseudonyms()
  })

  afterEach(async () => {
    vi.unstubAllGlobals()
    await clearPseudonyms()
  })

  it("create_pseudonym generates keypair and returns encrypted blob", async () => {
    const walletAddress = "0xabc123"
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)
    await pushServerEvent("create_pseudonym", {})

    expect(wallet._calls.signPersonalMessage).toHaveLength(1)
    expect(wallet._calls.signPersonalMessage[0].message).toEqual(deterministicMessage)

    expect(events).toContainEqual({
      event: "pseudonym_created",
      payload: {
        pseudonym_address: expect.stringMatching(/^0x[0-9a-f]+$/),
        encrypted_private_key: expect.stringMatching(/^[A-Za-z0-9+/=]+$/)
      }
    })

    expect(events.find((event) => event.event === "pseudonym_error")).toBeUndefined()

    destroy()
  })

  it("encryption key derivation is deterministic", async () => {
    const walletAddress = "0xabc123"
    const { created } = await createEncryptedPseudonym(walletAddress)

    const firstLoad = mountHook(await loadHook(), {
      id: "pseudonym-key-load-1",
      dataset: pseudonymHookDataset(walletAddress)
    })

    const secondLoad = mountHook(await loadHook(), {
      id: "pseudonym-key-load-2",
      dataset: pseudonymHookDataset(walletAddress)
    })

    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    registerWallet(wallet)

    await firstLoad.pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: created.payload.pseudonym_address,
          encrypted_key: created.payload.encrypted_private_key
        }
      ],
      active_address: created.payload.pseudonym_address
    })

    await secondLoad.pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: created.payload.pseudonym_address,
          encrypted_key: created.payload.encrypted_private_key
        }
      ],
      active_address: created.payload.pseudonym_address
    })

    expect(firstLoad.findEvent("pseudonyms_loaded").payload).toEqual({
      addresses: [created.payload.pseudonym_address],
      active_address: created.payload.pseudonym_address
    })

    expect(secondLoad.findEvent("pseudonyms_loaded").payload).toEqual({
      addresses: [created.payload.pseudonym_address],
      active_address: created.payload.pseudonym_address
    })

    firstLoad.destroy()
    secondLoad.destroy()
  })

  it("encrypted private key round-trips correctly", async () => {
    const walletAddress = "0xabc123"
    const { created } = await createEncryptedPseudonym(walletAddress)

    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-load",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: created.payload.pseudonym_address,
          encrypted_key: created.payload.encrypted_private_key
        }
      ],
      active_address: created.payload.pseudonym_address
    })

    expect(events).toContainEqual({
      event: "pseudonyms_loaded",
      payload: {
        addresses: [created.payload.pseudonym_address],
        active_address: created.payload.pseudonym_address
      }
    })

    expect(await activePseudonymAddress()).toBe(created.payload.pseudonym_address)

    destroy()
  })

  it("load_pseudonyms caches all keys when all blobs decrypt", async () => {
    const walletAddress = "0xabc123"
    const first = await createEncryptedPseudonym(walletAddress)
    const second = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-load",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: first.created.payload.pseudonym_address,
          encrypted_key: first.created.payload.encrypted_private_key
        },
        {
          address: second.created.payload.pseudonym_address,
          encrypted_key: second.created.payload.encrypted_private_key
        }
      ],
      active_address: first.created.payload.pseudonym_address
    })

    expect(events).toContainEqual({
      event: "pseudonyms_loaded",
      payload: {
        addresses: [
          first.created.payload.pseudonym_address,
          second.created.payload.pseudonym_address
        ],
        active_address: first.created.payload.pseudonym_address
      }
    })

    destroy()
  })

  it("sign_pseudonym_tx produces valid signature", async () => {
    const walletAddress = "0xabc123"
    const { created } = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-sign",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: created.payload.pseudonym_address,
          encrypted_key: created.payload.encrypted_private_key
        }
      ],
      active_address: created.payload.pseudonym_address
    })

    await pushServerEvent("sign_pseudonym_tx", {
      pseudonym_address: created.payload.pseudonym_address,
      tx_bytes: Buffer.from([1, 2, 3, 4]).toString("base64")
    })

    expect(events).toContainEqual({
      event: "pseudonym_tx_signed",
      payload: {
        signature: expect.any(String)
      }
    })

    destroy()
  })

  it("sign_pseudonym_tx errors when keypair not cached", async () => {
    const walletAddress = "0xabc123"
    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-sign-missing",
      dataset: pseudonymHookDataset(walletAddress)
    })

    await pushServerEvent("sign_pseudonym_tx", {
      pseudonym_address: "0xmissing",
      tx_bytes: Buffer.from([1, 2, 3]).toString("base64")
    })

    expect(events).toContainEqual({
      event: "pseudonym_error",
      payload: {
        reason: "keypair_not_found",
        phase: "sign"
      }
    })

    destroy()
  })

  it("load_pseudonyms activates requested keypair", async () => {
    const walletAddress = "0xabc123"
    const first = await createEncryptedPseudonym(walletAddress)
    const second = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-load-requested",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: first.created.payload.pseudonym_address,
          encrypted_key: first.created.payload.encrypted_private_key
        },
        {
          address: second.created.payload.pseudonym_address,
          encrypted_key: second.created.payload.encrypted_private_key
        }
      ],
      active_address: second.created.payload.pseudonym_address
    })

    expect(await activePseudonymAddress()).toBe(second.created.payload.pseudonym_address)

    destroy()
  })

  it("load_pseudonyms falls back to first key when active blob fails", async () => {
    const walletAddress = "0xabc123"
    const first = await createEncryptedPseudonym(walletAddress)
    const second = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-load-fallback",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: first.created.payload.pseudonym_address,
          encrypted_key: first.created.payload.encrypted_private_key
        },
        {
          address: second.created.payload.pseudonym_address,
          encrypted_key: `${second.created.payload.encrypted_private_key}corrupted`
        }
      ],
      active_address: second.created.payload.pseudonym_address
    })

    expect(events).toContainEqual({
      event: "pseudonyms_loaded",
      payload: {
        addresses: [first.created.payload.pseudonym_address],
        active_address: first.created.payload.pseudonym_address
      }
    })

    expect(await activePseudonymAddress()).toBe(first.created.payload.pseudonym_address)

    destroy()
  })

  it("load_pseudonyms activates first key when no active requested", async () => {
    const walletAddress = "0xabc123"
    const first = await createEncryptedPseudonym(walletAddress)
    const second = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-load-default",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: first.created.payload.pseudonym_address,
          encrypted_key: first.created.payload.encrypted_private_key
        },
        {
          address: second.created.payload.pseudonym_address,
          encrypted_key: second.created.payload.encrypted_private_key
        }
      ],
      active_address: null
    })

    expect(events).toContainEqual({
      event: "pseudonyms_loaded",
      payload: {
        addresses: [
          first.created.payload.pseudonym_address,
          second.created.payload.pseudonym_address
        ],
        active_address: first.created.payload.pseudonym_address
      }
    })

    expect(await activePseudonymAddress()).toBe(first.created.payload.pseudonym_address)

    destroy()
  })

  it("activate_pseudonym switches active keypair", async () => {
    const walletAddress = "0xabc123"
    const first = await createEncryptedPseudonym(walletAddress)
    const second = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-activate",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: first.created.payload.pseudonym_address,
          encrypted_key: first.created.payload.encrypted_private_key
        },
        {
          address: second.created.payload.pseudonym_address,
          encrypted_key: second.created.payload.encrypted_private_key
        }
      ],
      active_address: first.created.payload.pseudonym_address
    })

    await pushServerEvent("activate_pseudonym", {
      pseudonym_address: second.created.payload.pseudonym_address
    })

    expect(events).toContainEqual({
      event: "pseudonym_activated",
      payload: {
        pseudonym_address: second.created.payload.pseudonym_address
      }
    })

    expect(await activePseudonymAddress()).toBe(second.created.payload.pseudonym_address)

    destroy()
  })

  it("activate_pseudonym errors for uncached address", async () => {
    const walletAddress = "0xabc123"
    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-activate-missing",
      dataset: pseudonymHookDataset(walletAddress)
    })

    await pushServerEvent("activate_pseudonym", {
      pseudonym_address: "0xmissing"
    })

    expect(events).toContainEqual({
      event: "pseudonym_error",
      payload: {
        reason: "keypair_not_found",
        phase: "activate"
      }
    })

    destroy()
  })

  it("load_pseudonyms partially succeeds when one blob is corrupted", async () => {
    const walletAddress = "0xabc123"
    const first = await createEncryptedPseudonym(walletAddress)
    const second = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-partial-load",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: first.created.payload.pseudonym_address,
          encrypted_key: first.created.payload.encrypted_private_key
        },
        {
          address: second.created.payload.pseudonym_address,
          encrypted_key: "invalid-base64"
        }
      ],
      active_address: first.created.payload.pseudonym_address
    })

    expect(events).toContainEqual({
      event: "pseudonyms_loaded",
      payload: {
        addresses: [first.created.payload.pseudonym_address],
        active_address: first.created.payload.pseudonym_address
      }
    })

    expect(events.find((event) => event.event === "pseudonym_error")).toBeUndefined()

    destroy()
  })

  it("load_pseudonyms emits error when all blobs fail", async () => {
    const walletAddress = "0xabc123"
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-full-failure",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: "0xdeadbeef",
          encrypted_key: "not-a-valid-blob"
        }
      ],
      active_address: "0xdeadbeef"
    })

    expect(events).toContainEqual({
      event: "pseudonym_error",
      payload: {
        reason: "decrypt_failed",
        phase: "load"
      }
    })

    destroy()
  })

  it("load_pseudonyms with empty list clears state", async () => {
    const walletAddress = "0xabc123"
    const { created } = await createEncryptedPseudonym(walletAddress)
    const wallet = createMockWallet({
      accounts: [{ address: walletAddress, chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-clear",
      dataset: pseudonymHookDataset(walletAddress)
    })

    registerWallet(wallet)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [
        {
          address: created.payload.pseudonym_address,
          encrypted_key: created.payload.encrypted_private_key
        }
      ],
      active_address: created.payload.pseudonym_address
    })

    expect(await activePseudonymAddress()).toBe(created.payload.pseudonym_address)

    await pushServerEvent("load_pseudonyms", {
      encrypted_keys: [],
      active_address: null
    })

    expect(events).toContainEqual({
      event: "pseudonyms_loaded",
      payload: {
        addresses: [],
        active_address: null
      }
    })

    expect(await activePseudonymAddress()).toBeNull()

    destroy()
  })

  it("create_pseudonym errors when no wallet available", async () => {
    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "pseudonym-key-no-wallet",
      dataset: pseudonymHookDataset()
    })

    await pushServerEvent("create_pseudonym", {})

    expect(events).toContainEqual({
      event: "pseudonym_error",
      payload: {
        reason: "no_wallet",
        phase: "encrypt"
      }
    })

    destroy()
  })
})
