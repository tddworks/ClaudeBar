# Mistral: design

Contributor notes for Mistral. User-facing setup is in [README.md](README.md).

## As data

Mistral is `Modules/Providers/Resources/Providers/mistral.json` and `mistral-logs.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2). Ported from #397.

- **Mistral has no meter.** ClaudeBar has no source for its plan quota or rate limits, so the definition reports no quota, never a made-up one. Its one data source is a `directory` fetch of `~/.vibe/logs/session/` (`session_*` entries): ready while the folder exists, which is the old "available once Vibe has run".
- **Today's usage is Usage History**, not usage (CANONICAL §1, §9): `mistral.json`'s `usageHistory` reads Vibe's `session_*/meta.json` files (`format: json`, the time from the folder's UTC name with `at.fromPath`, the session's own `session_cost`), so TODAY'S USAGE shows today's and yesterday's cost and tokens as before — `account.usageHistory`, run by `DataSources`' `UsageLog` (UH3). The usage no longer carries a `dailyUsageReport` for Mistral.

## Vibe's logs

Each session is a folder `session_YYYYMMDD_HHMMSS_<id>` with a `meta.json` holding `stats.session_total_llm_tokens` and `stats.session_cost` (Vibe's own cost; ClaudeBar applies no pricing). The folder name's timestamp is **UTC**: a session counts on the local day its UTC start falls in, so a 5 pm PST session isn't moved to the next day. A folder whose `meta.json` is missing or unreadable is skipped.
