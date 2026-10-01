---
description: Reference for extension authors. Lists every manifest.json field, the config field types, the section types, and the JSON each probe script must print.
---

# Extension manifest reference

Start with [README.md](README.md) for setup and how scripts run. A complete example is in [example-provider/](example-provider/manifest.json).

## `manifest.json`

| Field | Required | What it does |
|---|---|---|
| `id` | yes | Unique id. ClaudeBar's provider id becomes `ext-<id>`, so it never clashes with a built-in provider |
| `name` | yes | Name shown in the provider pills and Settings |
| `version` | yes | Any string. Not checked |
| `description` | no | Subtitle of the config card in Settings |
| `icon` | no | SF Symbol name (`"cpu.fill"`, `"network"`). Shown in the menu bar, popover, Touch Bar and Settings. An unknown name shows a question mark |
| `colors.primary` | no | Hex accent colour for the config card |
| `colors.gradient` | no | Array of hex colours. Accepted but not used yet |
| `dashboardURL` | no | Opened by the popover's Dashboard button |
| `statusPageURL` | no | The provider's status page |
| `config` | no | Settings fields, see [Config fields](#config-fields) |
| `sections` | yes | At least one, see [Sections](#sections) |

## Config fields

Each entry becomes a field in the extension's card in **Settings → Providers**, and its value is passed to every script as an environment variable.

| Field | Required | What it does |
|---|---|---|
| `id` | yes | Field id. `CLAUDEBAR_` plus this in upper snake case is the variable name |
| `label` | yes | Field label |
| `type` | yes | One of the types below |
| `default` | no | Used until the user enters a value, and passed to scripts |
| `placeholder` | no | Hint text in an empty field |
| `helpText` | no | Line under the field |
| `options` | no | Choices, for `choice` only |
| `required` | no | Accepted, but not enforced yet. Have the script check for a missing value |

| `type` | Control | Stored in |
|---|---|---|
| `string` | Text field | `~/.claudebar/settings.json`, under `extensions.<id>.<fieldId>` |
| `path` | Text field | same |
| `number` | Text field | same, as text |
| `toggle` | Switch | same, as `"true"` / `"false"` |
| `choice` | Segmented picker | same |
| `secret` | Hidden field with a show button | ClaudeBar's app preferences (UserDefaults), never `settings.json` |

Every value reaches the script as a string.

| Field `id` | Variable |
|---|---|
| `apiKey` | `CLAUDEBAR_API_KEY` |
| `baseUrl` | `CLAUDEBAR_BASE_URL` |
| `base-url` | `CLAUDEBAR_BASE_URL` |
| `monthly_budget` | `CLAUDEBAR_MONTHLY_BUDGET` |

## Sections

| Field | Required | What it does |
|---|---|---|
| `id` | yes | Unique within the extension |
| `type` | yes | `quotaGrid`, `costUsage`, `dailyUsage`, `metricsRow`, `statusBanner` or `healthCheck` |
| `probe.command` | yes, unless `healthCheck` | Path of the executable to run. Relative to the extension folder unless it starts with `/`. No arguments |
| `probe.timeout` | no | Seconds before the script is stopped. Default `10` |
| `probe.interval` | no | Accepted but ignored. Every section runs on each refresh |

| `type` | Shows as |
|---|---|
| `quotaGrid` | Quota cards with a bar and reset time |
| `costUsage` | A cost card, with budget progress when `budget` is set |
| `dailyUsage` | Today-vs-previous cards for cost, tokens and working time |
| `metricsRow` | Cards with a value, unit, optional bar and optional change |
| `statusBanner` | Nothing yet (the output is checked, then dropped) |
| `healthCheck` | "Status" and "Latency" cards for a URL, no script |

### Health check

```json
{ "id": "health", "type": "healthCheck",
  "probe": { "builtIn": "healthCheck", "url": "https://api.example.com/health", "timeout": 5 } }
```

ClaudeBar sends a `HEAD` request to `url` and shows **UP** or **DOWN** with the status code, plus the latency. It's amber for a 4xx answer or a response slower than 2 s, and red for a 5xx answer or no response.

## What a script must print

One JSON object containing the key for its section type. Other keys are ignored. Dates in `resetsAt` are ISO 8601 (`2026-03-17T18:00:00Z`).

### `quotaGrid` → `quotas`

```json
{ "quotas": [
    { "type": "session", "percentRemaining": 97.0, "resetsAt": "2026-03-17T18:00:00Z" },
    { "type": "weekly", "percentRemaining": 69.0, "resetText": "Resets Monday" },
    { "type": "model:sonnet", "percentRemaining": 99.0, "dollarRemaining": 50.0 }
] }
```

- Required: `type` and `percentRemaining` (0 to 100).
- `type` is `session`, `weekly`, `model:<name>`, or any other text, which is shown as its own time-limited quota.
- Optional: `resetsAt`, `resetText` (free text such as "Resets Monday") and `dollarRemaining`.

### `costUsage` → `costUsage`

```json
{ "costUsage": { "totalCost": 10.26, "budget": 100.0, "apiDuration": 454.0,
                 "wallDuration": 23600.0, "linesAdded": 150, "linesRemoved": 42 } }
```

Required: `totalCost` and `apiDuration` (seconds). The rest are optional.

### `dailyUsage` → `dailyUsage`

```json
{ "dailyUsage": {
    "today":    { "date": "2026-03-17", "totalCost": 10.26,  "totalTokens": 8300000, "workingTime": 454.0 },
    "previous": { "date": "2026-03-16", "totalCost": 711.84, "totalTokens": 8693000, "workingTime": 42514.0 }
} }
```

Both days are required, each with `date` (`yyyy-MM-dd`), `totalCost`, `totalTokens` (an integer) and `workingTime` (seconds). `sessionCount` is optional. The cards show only with **Settings → General → Daily Usage Cards** on.

### `metricsRow` → `metrics`

```json
{ "metrics": [
    { "label": "API Calls", "value": "1,234", "unit": "Requests",
      "icon": "arrow.up.arrow.down", "color": "#4CAF50", "progress": 0.65,
      "delta": { "vs": "Yesterday", "value": "+200", "percent": 19.3 } }
] }
```

- Required: `label`, `value` and `unit`. **`value` must be a string** (`"1,234"`, not `1234`).
- Optional: `icon` (an SF Symbol), `color` (hex), `progress` (0.0 to 1.0) and `delta`. `delta` needs `vs` and `value`, and `percent` is optional.
- Keep `label` unique across the extension's metrics.

### `statusBanner` → `status`

```json
{ "status": { "text": "Connected", "level": "healthy" } }
```

`level` is `healthy`, `warning`, `critical` or `inactive`. The output must be valid, or the section counts as failed, but it isn't shown yet.
