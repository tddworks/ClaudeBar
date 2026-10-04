import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// The test Worker gets its own local bindings; deploy config is cloudflare.config.ts.
export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        main: "./src/index.ts",
        miniflare: {
          compatibilityDate: "2026-08-22",
          d1Databases: ["DB"],
          ratelimits: { JOIN_LIMITER: { namespace_id: "1001", simple: { limit: 5, period: 60 } } },
          bindings: { TEST_MIGRATIONS: migrations },
        },
      }),
    ],
    test: { setupFiles: ["./test/setup.ts"] },
  };
});
