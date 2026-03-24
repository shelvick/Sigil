import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { mountHook } from "./support/liveview_hook"

vi.mock("snarkjs", () => ({
  groth16: {
    fullProve: vi.fn()
  }
}))

const TEST_VECTOR_COMMITMENT =
  "15539519021302514881265614457483181390288297695578326223934756601408766449787"

const SUCCESS_PROOF = {
  pi_a: ["1", "2", "1"],
  pi_b: [
    ["3", "4"],
    ["5", "6"],
    ["1", "0"]
  ],
  pi_c: ["7", "8", "1"]
}

const artifactResponse = (bytes) => ({
  ok: true,
  arrayBuffer: vi.fn().mockResolvedValue(Uint8Array.from(bytes).buffer)
})

const installHappyPathMocks = () => {
  const fetchMock = vi.fn().mockImplementation((url) => {
    const path = String(url)

    if (path.includes("intel_commitment.wasm")) {
      return Promise.resolve(artifactResponse([1, 2, 3]))
    }

    if (path.includes("intel_commitment_final.zkey")) {
      return Promise.resolve(artifactResponse([4, 5, 6]))
    }

    return Promise.reject(new Error(`unexpected fetch: ${path}`))
  })

  Object.defineProperty(globalThis, "fetch", {
    configurable: true,
    writable: true,
    value: fetchMock
  })

  Object.defineProperty(globalThis, "crypto", {
    configurable: true,
    value: {
      subtle: {
        digest: vi.fn(async (_algorithm, input) => {
          const bytes = new Uint8Array(32)
          const inputBytes = new Uint8Array(input)
          bytes[31] = inputBytes.length || 1
          return bytes.buffer
        })
      }
    }
  })
}

let ZkProofGenerator
let snarkjs

describe("ZkProofGenerator hook", () => {
  beforeEach(async () => {
    vi.restoreAllMocks()
    vi.resetModules()

    installHappyPathMocks()

    snarkjs = await import("snarkjs")
    snarkjs.groth16.fullProve.mockResolvedValue({
      proof: SUCCESS_PROOF,
      publicSignals: [TEST_VECTOR_COMMITMENT]
    })

    const hookModulePath = "../hooks/zk_proof_hook"
    ;({ default: ZkProofGenerator } = await import(/* @vite-ignore */ hookModulePath))
  })

  afterEach(() => {
    vi.restoreAllMocks()
    Reflect.deleteProperty(globalThis, "fetch")
    Reflect.deleteProperty(globalThis, "crypto")
  })

  it("generates valid proof from intel data", async () => {
    const { pushServerEvent, events, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id: "0xabc123",
      notes: "Enemy gate online"
    })

    const generated = events.find((event) => event.event === "proof_generated")
    expect(generated).toBeDefined()
    expect(generated.payload.proof_points).toMatch(/\S+/)
    expect(generated.payload.public_inputs).toMatch(/\S+/)
    expect(generated.payload.commitment).toMatch(/^\d+$/)

    destroy()
  })

  it("commitment matches canonical test vector witness", async () => {
    const { pushServerEvent, events, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof_test_vector", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id_field: "42",
      content_hash_field: "123456789"
    })

    const generated = events.find((event) => event.event === "proof_generated")
    expect(generated).toBeDefined()
    expect(generated.payload.commitment).toBe(TEST_VECTOR_COMMITMENT)

    destroy()
  })

  it("proof_points encodes to 256 bytes", async () => {
    const { pushServerEvent, events, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof_test_vector", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id_field: "42",
      content_hash_field: "123456789"
    })

    const generated = events.find((event) => event.event === "proof_generated")
    const proofBytes = Uint8Array.from(atob(generated.payload.proof_points), (char) =>
      char.charCodeAt(0)
    )

    expect(proofBytes).toHaveLength(256)

    destroy()
  })

  it("public_inputs encodes to 32 bytes", async () => {
    const { pushServerEvent, events, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof_test_vector", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id_field: "42",
      content_hash_field: "123456789"
    })

    const generated = events.find((event) => event.event === "proof_generated")
    const publicInputBytes = Uint8Array.from(atob(generated.payload.public_inputs), (char) =>
      char.charCodeAt(0)
    )

    expect(publicInputBytes).toHaveLength(32)

    destroy()
  })

  it("hashAssemblyId produces deterministic output", async () => {
    const { hook, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    const first = await hook.hashAssemblyId("0xabc123")
    const second = await hook.hashAssemblyId("0xabc123")

    expect(first).toBe(second)
    expect(BigInt(first)).toBeGreaterThanOrEqual(0n)

    destroy()
  })

  it("hashNotes handles empty string", async () => {
    const { hook, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    const hashed = await hook.hashNotes("")

    expect(BigInt(hashed)).toBeGreaterThanOrEqual(0n)
    expect(BigInt(hashed)).toBeLessThan(
      21888242871839275222246405745257275088548364400416034343698204186575808495617n
    )

    destroy()
  })

  it("pushes proof_error when circuit files unavailable", async () => {
    global.fetch.mockRejectedValueOnce(new Error("missing wasm"))

    const { pushServerEvent, events, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id: "0xabc123",
      notes: "Enemy gate online"
    })

    const error = events.find((event) => event.event === "proof_error")
    expect(error).toBeDefined()
    expect(error.payload.reason).toMatch(/load circuit|missing wasm/i)

    destroy()
  })

  it("pushes proof_status progress events", async () => {
    const { pushServerEvent, findEvents, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof_test_vector", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id_field: "42",
      content_hash_field: "123456789"
    })

    expect(findEvents("proof_status").map((event) => event.payload.status)).toEqual([
      "loading_circuit",
      "generating_witness",
      "generating_proof"
    ])

    destroy()
  })

  it("caches circuit artifacts after first load", async () => {
    const { pushServerEvent, destroy } = mountHook(ZkProofGenerator, {
      id: "zk-proof-generator"
    })

    await pushServerEvent("generate_proof_test_vector", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id_field: "42",
      content_hash_field: "123456789"
    })

    await pushServerEvent("generate_proof_test_vector", {
      report_type: 1,
      solar_system_id: 30000142,
      assembly_id_field: "42",
      content_hash_field: "123456789"
    })

    expect(global.fetch).toHaveBeenCalledTimes(2)

    destroy()
  })
})
