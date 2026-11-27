import { defineConfig } from "vitest/config";

// Tests run in plain Node (web-standard fetch / WebCrypto are built in) with a
// single worker, which keeps memory usage low on small machines. Outbound
// HTTP is always mocked: no test talks to a real external API.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
    fileParallelism: false,
    maxWorkers: 1,
    testTimeout: 15_000,
    restoreMocks: true,
  },
});
