import { defineConfig } from "vitest/config";

// The end-to-end suite: builds the fixture vault, serves it, and drives the
// built page in a real browser. Slow by nature (a site build plus a browser
// launch), so it is kept out of the default `npm test` and run on demand with
// `npm run test:e2e`.
export default defineConfig({
  test: {
    include: ["tests/e2e/**/*.test.ts"],
    testTimeout: 120_000,
    hookTimeout: 120_000,
    // A browser and a port are shared process-wide; one file at a time.
    fileParallelism: false,
  },
});
