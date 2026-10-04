import { bindings, defineConfig, triggers } from "cf/config";

// ClaudeBar Leaderboard API. See docs/features/leaderboard/design.md.
// D1 migrations live in ./migrations: `cf d1 migrations apply <database id> --dir migrations`.
// Invocation logs are off: they would record client IPs and headers.

export default defineConfig({
	worker: {
		name: "claudebar-leaderboard",
		compatibilityDate: "2026-08-22",
		entrypoint: "src/index.ts",
		observability: {
			enabled: true,
			logs: {
				invocationLogs: false,
			},
		},
		triggers: [
			// The API's address, baked into the app. DNS: a proxied AAAA 100:: record.
			triggers.fetch({ pattern: "claudebar-api.tddworks.com/*", zone: "tddworks.com" }),
			triggers.scheduled({
				schedule: "0 * * * *",
			}),
		],
		env: {
			DB: bindings.d1({
				name: "claudebar-leaderboard",
				id: "47a18949-32a1-4f55-b537-b40c3462b5b0",
			}),
			JOIN_LIMITER: bindings.rateLimit({
				namespace: "1001",
				simple: {
					limit: 5,
					period: 60,
				},
			}),
			RENAME_LIMITER: bindings.rateLimit({
				namespace: "1002",
				simple: {
					limit: 5,
					period: 60,
				},
			}),
		},
	},
});
