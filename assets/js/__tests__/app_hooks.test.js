import { describe, it, expect } from "vitest"
import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const appJsPath = path.resolve(__dirname, "../app.js")

describe("app hook registration", () => {
  it("registers marketplace hooks in LiveSocket hooks", async () => {
    const source = await readFile(appJsPath, "utf8")

    expect(source).toMatch(/import\s+SealEncrypt\s+from\s+["']\.\/hooks\/seal_hook["']/)
    expect(source).toMatch(/SealEncrypt\s*:\s*SealEncrypt/)
    expect(source).toMatch(/import\s+PseudonymKey\s+from\s+["']\.\/hooks\/pseudonym_hook["']/)
    expect(source).toMatch(/PseudonymKey\s*:\s*PseudonymKey/)
  })
})
