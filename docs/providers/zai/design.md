# Z.ai: design

Research notes for Z.ai (GLM Coding Plan), from the code, [#22](https://github.com/tddworks/ClaudeBar/pull/22), [#181](https://github.com/tddworks/ClaudeBar/pull/181) and [#240](https://github.com/tddworks/ClaudeBar/pull/240).

## Source

`GET <platform>/api/monitor/usage/quota/limit` with `Authorization: Bearer <key>`, `Accept-Language: en-US,en`. HTTP 401/403 → *Key needed*.

| Base URL seen in Claude's config contains | Platform queried |
|---|---|
| `api.z.ai` | `https://api.z.ai` |
| `open.bigmodel.cn` | `https://open.bigmodel.cn` (Zhipu) |
| `dev.bigmodel.cn` | `https://dev.bigmodel.cn` |

## As data

Z.ai is `Modules/Providers/Resources/Providers/zai.json` and `zai-usage.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names it. Ported from #392.

- **The key and its host travel together.** The credential is a `firstOf`: the saved `apiKey` setting, Claude Code's settings file, then an environment variable. Each one yields a `token` and a `baseURL`, and the request goes to `https://{{baseURL#host}}/api/monitor/usage/quota/limit`. A saved key or an environment key gets its `baseURL` from the `platform` choice setting (`with`); the file gives its own.
- **A file key is used only for a Z.ai host.** `jsonFile` reads `env.ANTHROPIC_AUTH_TOKEN`/`env.ANTHROPIC_BASE_URL`, then `providers[0].api_key`/`base_url`, then top-level `api_key`; `match` refuses the record unless `baseURL` is on `api.z.ai`, `open.bigmodel.cn` or `dev.bigmodel.cn` (anchored, so `api.z.ai.example.com` is not one). The old probe also searched the whole file for a host, which could pair one entry's key with another's URL; that's gone, as is the `claude`-on-PATH check, which the quota API never needed.
- **Environment.** `glmAuthEnvVar` defaults to `ZAI_API_KEY`. The composition root reads a variable the person named through `ShellEnvironment` (the app's environment, then the login shell via `LoginShellEnvironment`, whose name check and markers are unchanged). Only a named variable: availability checks run the same lookup, and an unconditional shell would run for everyone who doesn't use Z.ai.
- **Errors.** 401 and 403 are *Key needed*; no key anywhere is *Key needed*.
- **Accounts.** An added account is a key and a platform (`accounts.patch`); it never reads the file or the environment.
- **Compatibility.** The saved key moves from its old Keychain name through `ProviderVault.legacyKeys`; `zai.configPath` and `zai.glmAuthEnvVar` are already `<id>.<setting>`. A leading `~` in the path is now expanded.

## Response

```json
{
  "code": 200,
  "data": {
    "limits": [
      { "type": "CREDIT_LIMIT", "unit": 3, "number": 5, "usage": 2000,
        "currentValue": 0, "remaining": 2000, "percentage": 0 },
      { "type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": 10000,
        "currentValue": 2004, "remaining": 7995, "percentage": 20,
        "nextResetTime": 1786112351998 }
    ],
    "level": "lite"
  },
  "success": true
}
```

(A `lite` account, from #240, values redacted.) Only `type`, `unit`, `percentage` (percent **used**, clamped to 0–100) and `nextResetTime` are read. `nextResetTime` is epoch milliseconds as a number; ISO 8601 strings and epoch-seconds strings are accepted too.

### `unit` decides the window

Several entries share one `type` and differ only by `unit`. Mapping observed on the GLM Coding Plan, May 2026:

| `type` | `unit` | Shown as |
|---|---|---|
| `TIME_LIMIT` | any (seen: 5) | MCP (tools) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | 3 | 5-hour session (window 5 h) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | 6 | Weekly (window 7 d) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | 7 | Monthly (plan-dependent, rare) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | missing | 5-hour session (responses before `unit` existed) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | other | "Tokens (unit N)" / "Credits (unit N)", kept rather than dropped |

Only units 3 and 6 state a window; the rest have none rather than a guessed one (the Window law). Other types are skipped. If nothing is left → "No recognized quota types found".

History:

- Before #181 (0.4.61) every `TOKENS_LIMIT` became the session quota, so the weekly entry, the cap GLM users care about most, overwrote or was overwritten by the 5-hour one.
- Credit-based tiers report `CREDIT_LIMIT` with the same `unit` meanings. Before #240 (0.4.75) every entry fell through to "skip", and the probe failed on a valid HTTP 200.
