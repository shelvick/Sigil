import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { mountHook } from "./support/liveview_hook"
import { createMockWallet, registerWallet } from "./support/mock_wallet"

const sealClientConstructor = vi.fn()
const encryptMock = vi.fn()
const decryptMock = vi.fn()
const sessionKeyCreateMock = vi.fn()
const buildMock = vi.fn()
const setSenderMock = vi.fn()
const moveCallMock = vi.fn()
const objectMock = vi.fn((id) => ({ kind: "object", id }))
const pureVectorMock = vi.fn((_type, value) => ({ kind: "pure", value }))

vi.mock("@mysten/seal", () => ({
  SealClient: vi.fn().mockImplementation((opts) => {
    sealClientConstructor(opts)
    return {
      encrypt: encryptMock,
      decrypt: decryptMock
    }
  }),
  SessionKey: {
    create: sessionKeyCreateMock
  }
}))

vi.mock("@mysten/sui/jsonRpc", () => ({
  SuiJsonRpcClient: vi.fn().mockImplementation(({ url }) => ({ url }))
}))

vi.mock("@mysten/sui/transactions", () => ({
  Transaction: vi.fn().mockImplementation(() => ({
    setSenderIfNotSet: setSenderMock,
    moveCall: moveCallMock,
    object: objectMock,
    pure: {
      vector: pureVectorMock
    },
    build: buildMock
  }))
}))

const sealConfig = {
  seal_package_id: "0x" + "11".repeat(32),
  key_server_object_ids: ["0x" + "22".repeat(32), "0x" + "33".repeat(32)],
  threshold: 2,
  walrus_publisher_url: "https://publisher.example.test",
  walrus_aggregator_url: "https://aggregator.example.test",
  walrus_epochs: 15,
  sui_rpc_url: "https://rpc.example.test"
}

const intelPayload = {
  report_type: 1,
  solar_system_id: 30_000_142,
  assembly_id: "0xassembly",
  notes: "Enemy gate online",
  label: "Northern Outpost"
}

async function loadHook() {
  const module = await import("../hooks/seal_hook")
  return module.default
}

describe("SealEncrypt hook", () => {
  beforeEach(() => {
    vi.resetModules()
    vi.clearAllMocks()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it("encrypts intel data and uploads to Walrus", async () => {
    encryptMock.mockResolvedValue({ encryptedObject: new Uint8Array([1, 2, 3, 4]) })
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ newlyCreated: { blobObject: { blobId: "walrus-blob-123" } } })
      })
    )

    const providedSealId = "0x" + "aa".repeat(32)

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    await pushServerEvent("encrypt_and_upload", {
      intel_data: intelPayload,
      seal_id: providedSealId,
      config: sealConfig
    })

    expect(events.filter((event) => event.event === "seal_status").map((event) => event.payload.status)).toEqual([
      "encrypting",
      "uploading"
    ])

    expect(events).toContainEqual({
      event: "seal_upload_complete",
      payload: {
        blob_id: "walrus-blob-123",
        seal_id: providedSealId
      }
    })

    const encryptArgs = encryptMock.mock.calls[0][0]
    expect(encryptArgs.threshold).toBe(2)
    expect(encryptArgs.packageId).toBe(sealConfig.seal_package_id)
    expect(encryptArgs.id).toBe(providedSealId)
    expect(new TextDecoder().decode(encryptArgs.data)).toBe(JSON.stringify(intelPayload))

    destroy()
  })

  it("decrypts purchased listing from Walrus blob", async () => {
    const personalMessage = new Uint8Array([9, 9, 9])
    const setPersonalMessageSignature = vi.fn().mockResolvedValue(undefined)

    sessionKeyCreateMock.mockResolvedValue({
      getPersonalMessage: () => personalMessage,
      setPersonalMessageSignature
    })
    buildMock.mockResolvedValue(new Uint8Array([7, 7, 7]))
    decryptMock.mockResolvedValue(new TextEncoder().encode(JSON.stringify(intelPayload)))

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => new Uint8Array([5, 4, 3]).buffer
      })
    )

    const wallet = createMockWallet({
      accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    registerWallet(wallet)

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "aa".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(events.filter((event) => event.event === "seal_status").map((event) => event.payload.status)).toEqual([
      "fetching",
      "decrypting"
    ])
    expect(wallet._calls.signPersonalMessage).toHaveLength(1)
    expect(setPersonalMessageSignature).toHaveBeenCalledWith("dGVzdC1zaWduYXR1cmU=")
    expect(moveCallMock).toHaveBeenCalledWith(
      expect.objectContaining({
        target: `${sealConfig.seal_package_id}::seal_policy::seal_approve`
      })
    )
    expect(objectMock).toHaveBeenCalledWith("0xlisting")
    expect(events).toContainEqual({
      event: "seal_decrypt_complete",
      payload: { data: JSON.stringify(intelPayload) }
    })

    destroy()
  })

  it("encrypt then decrypt produces identical data", async () => {
    const encryptedObject = new Uint8Array([1, 2, 3, 4])
    const providedSealId = "0x" + "ab".repeat(32)

    encryptMock.mockResolvedValue({ encryptedObject })
    decryptMock.mockResolvedValue(new TextEncoder().encode(JSON.stringify(intelPayload)))
    sessionKeyCreateMock.mockResolvedValue({
      getPersonalMessage: () => new Uint8Array([1]),
      setPersonalMessageSignature: vi.fn().mockResolvedValue(undefined)
    })
    buildMock.mockResolvedValue(new Uint8Array([7, 7, 7]))

    vi.stubGlobal(
      "fetch",
      vi.fn()
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ alreadyCertified: { blobId: "walrus-roundtrip-blob" } })
        })
        .mockResolvedValueOnce({
          ok: true,
          arrayBuffer: async () => encryptedObject.buffer
        })
    )

    const wallet = createMockWallet({
      accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    registerWallet(wallet)

    await pushServerEvent("encrypt_and_upload", {
      intel_data: intelPayload,
      seal_id: providedSealId,
      config: sealConfig
    })

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-roundtrip-blob",
      seal_id: providedSealId,
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(events).toContainEqual({
      event: "seal_upload_complete",
      payload: {
        blob_id: "walrus-roundtrip-blob",
        seal_id: providedSealId
      }
    })
    expect(events).toContainEqual({
      event: "seal_decrypt_complete",
      payload: { data: JSON.stringify(intelPayload) }
    })

    destroy()
  })

  it("pushes encryption progress status events", async () => {
    const providedSealId = "0x" + "ac".repeat(32)

    encryptMock.mockResolvedValue({ encryptedObject: new Uint8Array([1]) })
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ newlyCreated: { blobObject: { blobId: "walrus-blob-123" } } })
      })
    )

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: { config: JSON.stringify(sealConfig) }
    })

    await pushServerEvent("encrypt_and_upload", {
      intel_data: intelPayload,
      seal_id: providedSealId,
      config: sealConfig
    })

    expect(events.filter((event) => event.event === "seal_status").map((event) => event.payload.status)).toEqual([
      "encrypting",
      "uploading"
    ])

    const encryptArgs = encryptMock.mock.calls[0][0]
    expect(encryptArgs.id).toBe(providedSealId)
    expect(new TextDecoder().decode(encryptArgs.data)).toBe(JSON.stringify(intelPayload))

    destroy()
  })

  it("pushes decryption progress status events", async () => {
    sessionKeyCreateMock.mockResolvedValue({
      getPersonalMessage: () => new Uint8Array([1]),
      setPersonalMessageSignature: vi.fn().mockResolvedValue(undefined)
    })
    buildMock.mockResolvedValue(new Uint8Array([7, 7, 7]))
    decryptMock.mockResolvedValue(new TextEncoder().encode(JSON.stringify(intelPayload)))
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => new Uint8Array([5, 4, 3]).buffer
      })
    )

    const wallet = createMockWallet({
      accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    registerWallet(wallet)

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "ad".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(events.filter((event) => event.event === "seal_status").map((event) => event.payload.status)).toEqual([
      "fetching",
      "decrypting"
    ])
    expect(events).toContainEqual({
      event: "seal_decrypt_complete",
      payload: { data: JSON.stringify(intelPayload) }
    })

    destroy()
  })

  it("Walrus upload failure pushes seal_error", async () => {
    const providedSealId = "0x" + "ae".repeat(32)

    encryptMock.mockResolvedValue({ encryptedObject: new Uint8Array([1, 2, 3, 4]) })
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 503
      })
    )

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: { config: JSON.stringify(sealConfig) }
    })

    await pushServerEvent("encrypt_and_upload", {
      intel_data: intelPayload,
      seal_id: providedSealId,
      config: sealConfig
    })

    expect(events).toContainEqual({
      event: "seal_error",
      payload: expect.objectContaining({ phase: "upload" })
    })

    const encryptArgs = encryptMock.mock.calls[0][0]
    expect(encryptArgs.id).toBe(providedSealId)
    expect(new TextDecoder().decode(encryptArgs.data)).toBe(JSON.stringify(intelPayload))

    destroy()
  })

  it("missing Walrus blob pushes seal_error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 404
      })
    )

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-missing",
      seal_id: "0x" + "af".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(events).toContainEqual({
      event: "seal_error",
      payload: expect.objectContaining({ phase: "fetch" })
    })

    destroy()
  })

  it("subsequent encrypt request reuses initialized clients", async () => {
    const firstSealId = "0x" + "ba".repeat(32)
    const secondSealId = "0x" + "bb".repeat(32)
    const updatedPayload = { ...intelPayload, notes: "Updated note" }

    encryptMock.mockResolvedValue({ encryptedObject: new Uint8Array([1, 2, 3, 4]) })
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ newlyCreated: { blobObject: { blobId: "walrus-blob-123" } } })
      })
    )

    const { pushServerEvent, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: { config: JSON.stringify(sealConfig) }
    })

    await pushServerEvent("encrypt_and_upload", {
      intel_data: intelPayload,
      seal_id: firstSealId,
      config: sealConfig
    })

    await pushServerEvent("encrypt_and_upload", {
      intel_data: updatedPayload,
      seal_id: secondSealId,
      config: sealConfig
    })

    expect(sealClientConstructor).toHaveBeenCalledTimes(1)
    expect(encryptMock.mock.calls[0][0].id).toBe(firstSealId)
    expect(new TextDecoder().decode(encryptMock.mock.calls[0][0].data)).toBe(JSON.stringify(intelPayload))
    expect(encryptMock.mock.calls[1][0].id).toBe(secondSealId)
    expect(new TextDecoder().decode(encryptMock.mock.calls[1][0].data)).toBe(JSON.stringify(updatedPayload))

    destroy()
  })

  it("missing wallet address pushes seal_error", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => new Uint8Array([5, 4, 3]).buffer
      })
    )

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: { config: JSON.stringify(sealConfig) }
    })

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "bc".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(events).toContainEqual({
      event: "seal_error",
      payload: expect.objectContaining({ phase: "init" })
    })

    destroy()
  })

  it("decrypt flow reuses connected wallet account", async () => {
    sessionKeyCreateMock.mockResolvedValue({
      getPersonalMessage: () => new Uint8Array([1]),
      setPersonalMessageSignature: vi.fn().mockResolvedValue(undefined)
    })
    buildMock.mockResolvedValue(new Uint8Array([7, 7, 7]))
    decryptMock.mockResolvedValue(new TextEncoder().encode(JSON.stringify(intelPayload)))
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => new Uint8Array([5, 4, 3]).buffer
      })
    )

    const wallet = createMockWallet({
      accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
    })
    wallet.accounts = [{ address: "0xabc123", chains: ["sui:testnet"] }]

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    registerWallet(wallet)

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "bd".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "bd".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(wallet._calls.connect).toHaveLength(0)
    expect(wallet._calls.signPersonalMessage).toHaveLength(2)
    expect(events).toContainEqual({
      event: "seal_decrypt_complete",
      payload: { data: JSON.stringify(intelPayload) }
    })

    destroy()
  })

  it("selects the wallet that owns the target address", async () => {
    sessionKeyCreateMock.mockResolvedValue({
      getPersonalMessage: () => new Uint8Array([1]),
      setPersonalMessageSignature: vi.fn().mockResolvedValue(undefined)
    })
    buildMock.mockResolvedValue(new Uint8Array([7, 7, 7]))
    decryptMock.mockResolvedValue(new TextEncoder().encode(JSON.stringify(intelPayload)))
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => new Uint8Array([5, 4, 3]).buffer
      })
    )

    const wrongWallet = createMockWallet({
      accounts: [{ address: "0xdef456", chains: ["sui:testnet"] }]
    })
    const rightWallet = createMockWallet({
      accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    registerWallet(wrongWallet)
    registerWallet(rightWallet)

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "bf".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(wrongWallet._calls.connect).toHaveLength(1)
    expect(wrongWallet._calls.signPersonalMessage).toHaveLength(0)
    expect(rightWallet._calls.connect).toHaveLength(1)
    expect(rightWallet._calls.signPersonalMessage).toHaveLength(1)
    expect(events).toContainEqual({
      event: "seal_decrypt_complete",
      payload: { data: JSON.stringify(intelPayload) }
    })

    destroy()
  })

  it("decrypt authorization PTB targets seal_policy with listing id", async () => {
    sessionKeyCreateMock.mockResolvedValue({
      getPersonalMessage: () => new Uint8Array([1]),
      setPersonalMessageSignature: vi.fn().mockResolvedValue(undefined)
    })
    buildMock.mockResolvedValue(new Uint8Array([7, 7, 7]))
    decryptMock.mockResolvedValue(new TextEncoder().encode(JSON.stringify(intelPayload)))
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        arrayBuffer: async () => new Uint8Array([5, 4, 3]).buffer
      })
    )

    const wallet = createMockWallet({
      accounts: [{ address: "0xabc123", chains: ["sui:testnet"] }]
    })

    const { pushServerEvent, events, destroy } = mountHook(await loadHook(), {
      id: "seal-encrypt",
      dataset: {
        address: "0xabc123",
        suiChain: "sui:testnet",
        config: JSON.stringify(sealConfig)
      }
    })

    registerWallet(wallet)

    await pushServerEvent("decrypt_intel", {
      blob_id: "walrus-blob-123",
      seal_id: "0x" + "be".repeat(32),
      listing_id: "0xlisting",
      config: sealConfig
    })

    expect(moveCallMock).toHaveBeenCalledWith(
      expect.objectContaining({
        target: `${sealConfig.seal_package_id}::seal_policy::seal_approve`
      })
    )
    expect(objectMock).toHaveBeenCalledWith("0xlisting")
    expect(pureVectorMock).toHaveBeenCalledWith(
      "u8",
      expect.arrayContaining([190])
    )
    expect(events).toContainEqual({
      event: "seal_decrypt_complete",
      payload: { data: JSON.stringify(intelPayload) }
    })

    destroy()
  })
})
