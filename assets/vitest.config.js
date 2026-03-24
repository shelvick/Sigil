import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    environment: "jsdom",
    root: "js",
    include: ["**/*.test.js"],
    globals: true
  },
  resolve: {
    alias: {
      snarkjs: new URL("js/__mocks__/snarkjs.js", import.meta.url).pathname
    }
  }
})
