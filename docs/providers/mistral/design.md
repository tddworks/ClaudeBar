# Mistral: design

Contributor notes for Mistral. User-facing setup is in [README.md](README.md).

## As data

Mistral is `Modules/Providers/Resources/Providers/mistral.json` with `mistral-logs.js` and `mistral-plan.js`, run by the generic [engine](../../architecture/ENGINE_DESIGN.md). Ported from #397; the plan source came from #496, on research from #209.

- **Two data sources, the logs first.** `defaultDataSource` is `logs`; the card is ready while the Vibe logs folder exists, which is the old "available once Vibe has run". The `web` source adds the plan when the person gives it a session.
- **The logs source** is a `directory` fetch of `~/.vibe/logs/session/` (`session_*` entries), mapped by `mistral-logs.js`.
- **The web source** signs in with the person's chat.mistral.ai session: the pasted `cookie` setting, else `MISTRAL_CHAT_COOKIE`, else the browser's chat.mistral.ai cookies. It GETs `chat.mistral.ai/api/code-trpc/projects.list,apiKey.getApiKey,apiKey.getUsage?batch=1&input=…` with `Accept: application/json` and `trpc-accept: application/jsonl`, and `mistral-plan.js` reads the NDJSON answer: `usagePercentage` (used, 0–100) becomes `percentRemaining = 100 − usagePercentage`, and `resetAt` (ISO8601) becomes `resetsAt`, both as one `.timeLimit("Vibe plan")` quota. A refused cookie (401/403) is `sessionExpired`; an error object in the answer surfaces as `executionFailed`.
- **The browser fallback is best-effort by design.** The engine matches cookie names exactly, and the Ory session cookie's name is Mistral's own (`ory_session_…`), so a browser read finds at most `csrftoken`, which does not sign in. The pasted full `Cookie` header is the real path; the fallback stays in the definition so a future engine with suffix matching lights it up. Documented in the README's gotchas, not papered over.
- **Today's usage is Usage History**, not usage (CANONICAL §1, §9): `mistral.json`'s `usageHistory` reads Vibe's `session_*/meta.json` files (`format: json`, the time from the folder's UTC name with `at.fromPath`, the session's own `session_cost`), so TODAY'S USAGE shows today's and yesterday's cost and tokens as before — `account.usageHistory`, run by `DataSources`' `UsageLog` (UH3). The usage no longer carries a `dailyUsageReport` for Mistral.
- **Added logins bring their own cookie**: the `accounts.patch` pins the `web` source's credential to the login's `cookie` setting, so a second account never reads the first account's cookie or the browser's.

## Vibe's logs

Each session is a folder `session_YYYYMMDD_HHMMSS_<id>` with a `meta.json` holding `stats.session_total_llm_tokens` and `stats.session_cost` (Vibe's own cost; ClaudeBar applies no pricing). The folder name's timestamp is **UTC**: a session counts on the local day its UTC start falls in, so a 5 pm PST session isn't moved to the next day. A folder whose `meta.json` is missing or unreadable is skipped.
