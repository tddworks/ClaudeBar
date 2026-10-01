# Z.ai: probe design

Research notes for the Z.ai (GLM Coding Plan) probe, from the code, [#22](https://github.com/tddworks/ClaudeBar/pull/22), [#181](https://github.com/tddworks/ClaudeBar/pull/181) and [#240](https://github.com/tddworks/ClaudeBar/pull/240).

## Source

`GET <platform>/api/monitor/usage/quota/limit` with `Authorization: Bearer <key>`, `Accept-Language: en-US,en`. HTTP 401/403 → "Authentication required".

| Base URL seen in Claude's config contains | Platform queried |
|---|---|
| `api.z.ai` | `https://api.z.ai` |
| `open.bigmodel.cn` | `https://open.bigmodel.cn` (Zhipu) |
| `dev.bigmodel.cn` | `https://dev.bigmodel.cn` |

## Config discovery

Z.ai has no CLI of its own. Users point Claude Code at Z.ai's Anthropic-compatible endpoint, so the probe reads Claude Code's settings file (or the custom path) with `cat` and looks for:

1. **Platform**: `env.ANTHROPIC_BASE_URL`, then `providers[].base_url`, then any occurrence of one of the three hosts anywhere in the file. The last step lets unusual config shapes work. With no host found but an API key saved in ClaudeBar settings, the platform defaults to `https://api.z.ai`.
2. **Key**: the API key saved in ClaudeBar settings (Settings → Providers → Z.ai → API KEY), then `env.ANTHROPIC_AUTH_TOKEN`, then `providers[].api_key`, then top-level `api_key`, then the configured env var name.

`isAvailable` also requires `claude` on PATH, a leftover from treating Z.ai as "Claude Code pointed elsewhere". An API key saved in ClaudeBar settings skips that check entirely (and the config read) — the quota API never needs the CLI.

Known limits:

- The env var is read from `ProcessInfo.processInfo.environment`, the app's own environment. Launched from Finder or Login Items, that doesn't include shell rc exports ([#170](https://github.com/tddworks/ClaudeBar/issues/170)). When it misses, `LoginShellEnvironment` re-reads the variable through the user's interactive login shell (`$SHELL -l -i -c` via the probe's `CLIExecutor`), so both `~/.zshrc` and `~/.zprofile` get sourced. The name is validated against POSIX identifier syntax (ASCII) before interpolation, and the value is read between `@@CLAUDEBAR_BEGIN@@`/`@@CLAUDEBAR_END@@` markers printed by `printf` so rc-file noise can't concatenate onto it; marker-less output is discarded. The lookup never logs the value.
- The custom path goes through `URL(fileURLWithPath:)` and `cat` without a shell, so `~` isn't expanded.

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
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | 3 | 5-hour session |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | 6 | Weekly |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | 7 | Monthly (plan-dependent, rare) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | missing | 5-hour session (responses before `unit` existed) |
| `TOKENS_LIMIT` / `CREDIT_LIMIT` | other | "Tokens (unit N)" / "Credits (unit N)", kept rather than dropped |

Other types are skipped. If nothing is left → "No recognized quota types found".

History:

- Before #181 (0.4.61) every `TOKENS_LIMIT` became the session quota, so the weekly entry, the cap GLM users care about most, overwrote or was overwritten by the 5-hour one.
- Credit-based tiers report `CREDIT_LIMIT` with the same `unit` meanings. Before #240 (0.4.75) every entry fell through to "skip", and the probe failed on a valid HTTP 200.
