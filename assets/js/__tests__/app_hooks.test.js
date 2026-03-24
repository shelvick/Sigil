import { describe, it, expect } from "vitest"
import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const appJsPath = path.resolve(__dirname, "../app.js")

describe("app hook registration", () => {
  it("registers ZkProofGenerator in LiveSocket hooks", async () => {
    const source = await readFile(appJsPath, "utf8")

    expect(source).toMatch(/import\s+ZkProofGenerator\s+from\s+["']\.\/hooks\/zk_proof_hook["']/)
    expect(source).toMatch(/ZkProofGenerator\s*:\s*ZkProofGenerator/)
  })
})
