import { defineConfig } from "vitest/config";

// Unit tests only: the pure modules under src/lib, which run in milliseconds.
// The end-to-end tests under tests/e2e build a fixture vault and drive a real
// browser, so they live behind their own config (`npm run test:e2e`) rather than
// slowing this suite down.
export default defineConfig({
  test: {
    include: ["src/**/*.test.ts", "bin/**/*.test.mjs"],
  },
});
