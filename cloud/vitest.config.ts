import { defineConfig } from "vitest/config";

// Domain and MCP tests run in Node: the core has no Workers-specific dependencies,
// and the Durable Object is a thin adapter verified with `wrangler dev`.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
  },
});
