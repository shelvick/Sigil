import { groth16 } from "snarkjs"

const BN254_SCALAR_FIELD =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n

let cachedArtifacts = null

const ZkProofGenerator = {
  mounted() {
    this.handleEvent("generate_proof", async (payload) => {
      await this._generateProof(payload, false)
    })

    this.handleEvent("generate_proof_test_vector", async (payload) => {
      await this._generateProof(payload, true)
    })
  },

  async hashAssemblyId(assemblyId) {
    return this._hashToField(assemblyId || "")
  },

  async hashNotes(notes) {
    return this._hashToField(notes || "")
  },

  async _generateProof(payload, useTestVector) {
    try {
      this.pushEvent("proof_status", { status: "loading_circuit" })
      const artifacts = await this._loadArtifacts()

      this.pushEvent("proof_status", { status: "generating_witness" })
      const input = useTestVector
        ? {
            data: [
              payload.report_type,
              payload.solar_system_id,
              BigInt(payload.assembly_id_field).toString(),
              BigInt(payload.content_hash_field).toString()
            ]
          }
        : {
            data: [
              payload.report_type,
              payload.solar_system_id,
              await this.hashAssemblyId(payload.assembly_id),
              await this.hashNotes(payload.notes)
            ]
          }

      this.pushEvent("proof_status", { status: "generating_proof" })
      const { proof, publicSignals } = await groth16.fullProve(
        input,
        artifacts.wasm,
        artifacts.zkey
      )

      this.pushEvent("proof_generated", {
        proof_points: this._toBase64(this._encodeProofPoints(proof)),
        public_inputs: this._toBase64(this._encodePublicInputs(publicSignals)),
        commitment: String(publicSignals[0])
      })
    } catch (error) {
      const reason = error && error.message ? error.message : "Failed to load circuit"
      this.pushEvent("proof_error", { reason })
    }
  },

  async _loadArtifacts() {
    if (cachedArtifacts) {
      return cachedArtifacts
    }

    const [wasmResponse, zkeyResponse] = await Promise.all([
      fetch("/zk/intel_commitment.wasm"),
      fetch("/zk/intel_commitment_final.zkey")
    ])

    if (!wasmResponse.ok || !zkeyResponse.ok) {
      throw new Error("Failed to load circuit")
    }

    cachedArtifacts = {
      wasm: new Uint8Array(await wasmResponse.arrayBuffer()),
      zkey: new Uint8Array(await zkeyResponse.arrayBuffer())
    }

    return cachedArtifacts
  },

  async _hashToField(value) {
    const bytes = new TextEncoder().encode(value)
    const digest = await crypto.subtle.digest("SHA-256", bytes)
    const hex = Array.from(new Uint8Array(digest), (byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("")

    return (BigInt(`0x${hex}`) % BN254_SCALAR_FIELD).toString()
  },

  _encodeProofPoints(proof) {
    const values = [
      proof.pi_a[0],
      proof.pi_a[1],
      proof.pi_b[0][0],
      proof.pi_b[0][1],
      proof.pi_b[1][0],
      proof.pi_b[1][1],
      proof.pi_c[0],
      proof.pi_c[1]
    ]

    return this._concatBytes(values.map((value) => this._encodeScalarLE(value)))
  },

  _encodePublicInputs(publicSignals) {
    return this._concatBytes(publicSignals.map((value) => this._encodeScalarLE(value)))
  },

  _encodeScalarLE(value) {
    let remaining = BigInt(value)
    const bytes = new Uint8Array(32)

    for (let index = 0; index < 32; index += 1) {
      bytes[index] = Number(remaining & 0xffn)
      remaining >>= 8n
    }

    return bytes
  },

  _concatBytes(chunks) {
    const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0)
    const output = new Uint8Array(totalLength)
    let offset = 0

    chunks.forEach((chunk) => {
      output.set(chunk, offset)
      offset += chunk.length
    })

    return output
  },

  _toBase64(bytes) {
    return btoa(Array.from(bytes, (byte) => String.fromCharCode(byte)).join(""))
  }
}

export default ZkProofGenerator
