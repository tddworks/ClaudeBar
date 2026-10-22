---
description: Add a provider ClaudeBar doesn't ship by describing it in JSON — an API with your key, a CLI or a file — with Add Provider or Import in Settings, no script needed. Use when a service's usage is one HTTP call or one command away.
---

# Custom providers

A custom provider is a provider ClaudeBar doesn't ship, described in one JSON
file: where your key comes from, what to call, and how to read the answer into
quota cards. It runs on the same engine as the built-in providers, so it gets
the same cards, menu-bar readout, alerts and Test Connection — and its key field
is a real Settings field, kept in your Keychain.

**Custom provider or extension?** Use a custom provider when the usage is one
HTTP call (or one CLI command, or one file) and the numbers are in the answer.
Use an [extension](../extensions/README.md) when you need logic: several calls,
paging, sums, or anything you'd write a script for.

## The easy way: Add Provider

Settings → Providers → **Add Provider…** → *Start from* **API**, **CLI**,
**File** or **Copy a provider**. Fill in the address and the key, then
**Save & Test Connection**. The provider joins the list like any other.

## Writing the JSON yourself

Write the file anywhere, then Settings → Providers → **Import…**. Before
anything is saved, ClaudeBar shows what it would do: which host gets your key,
which commands it runs, and which key it needs. It is saved to
`~/.claudebar/providers/<id>.json`.

This is a whole provider for an API that reports a 5-hour and a weekly limit
([examples/acme-code.json](examples/acme-code.json)):

```json
{
  "profile": {
    "id": "acme-code",
    "name": "Acme Code",
    "links": { "dashboard": "https://acme.example/usage" },
    "look": { "symbol": "chevron.left.forwardslash.chevron.right" }
  },
  "settings": [
    { "id": "apiKey", "label": "API key", "kind": "secret", "scope": "account" },
    { "id": "authEnvVar", "label": "Environment variable", "default": "ACME_API_KEY" }
  ],
  "defaultDataSource": "api",
  "dataSources": [
    {
      "kind": "api",
      "label": "API",
      "summary": "Reads the 5-hour and weekly limits.",
      "credential": { "firstOf": [ { "environment": "{{setting.authEnvVar}}" }, { "setting": "apiKey" } ] },
      "fetch": {
        "http": {
          "url": "https://api.acme.example/v1/usage",
          "headers": { "Authorization": "Bearer {{token}}", "Accept": "application/json" },
          "timeout": 30
        }
      },
      "mapping": {
        "json": {
          "quotas": [
            { "kind": "session", "at": "$.five_hour", "usedPercent": "used_percent",
              "resetsAt": { "iso8601": "resets_at" }, "window": { "hours": 5 } },
            { "kind": "weekly", "at": "$.weekly", "usedPercent": "used_percent",
              "resetsAt": { "iso8601": "resets_at" }, "window": { "days": 7 } }
          ],
          "whenEmpty": { "otherwise": "No limits in the answer" }
        }
      }
    }
  ]
}
```

It reads an answer like [examples/acme-code.response.json](examples/acme-code.response.json):
`{ "five_hour": { "used_percent": 42, "resets_at": "…" }, "weekly": { … } }`
→ **Session 58% left**, **Weekly 90% left**, each with its reset.

| Part | What it says |
|---|---|
| `profile` | a unique `id`, the `name` on the card, a dashboard link, an SF Symbol |
| `dataSources` | the ways to read usage, each with a `kind` you name; `defaultDataSource` picks the first one tried |
| `settings` | the fields Settings shows. `"kind": "secret"` is a key: masked, kept in the Keychain, never in the file. `"scope": "account"` puts it on *Add Account* too, so you can watch a second key (a work account). `authEnvVar` names the environment variable to try first, editable in Settings |
| `credential` | where the key comes from, first that answers: the environment variable, then the `apiKey` setting. `{{token}}` is that key |
| `fetch.http` | the request: `url`, `headers`, optional `method`, `body`, `timeout` (seconds). `{{setting.x}}` fills in a plain setting |
| `mapping.json` | how the answer becomes quota cards — below |

## Reading the answer: `mapping.json`

Each entry in `quotas` is one card.

| Key | Means | Example |
|---|---|---|
| `kind` | `session` (5-hour), `weekly`, `model` or `time` (any other limit; give it a `name`) | `"kind": "model", "name": "Requests"` |
| `at` | the object the other keys read from | `"at": "$.five_hour"` |
| `usedPercent` / `leftPercent` | the percentage, under `at` | `"usedPercent": "used_percent"` |
| `left` | money instead of a percentage: left `of` a limit, or a balance with no `of` | `"left": { "money": "$.remaining", "of": "$.limit", "currency": "USD" }` |
| `resetsAt` | when it refills: `iso8601`, `epochSeconds` or `secondsFromNow` | `"resetsAt": { "iso8601": "resets_at" }` |
| `window` | the window's length: `hours`/`days` as a number, or `seconds`/`minutes` read from the answer | `"window": { "hours": 5 }` |
| `each` | one card per element of an array (with `name` read from it) | `"each": "$.limits"` |

`whenEmpty.otherwise` is the message shown when no card could be read.

A credit balance with a monthly limit is
[examples/acme-credits.json](examples/acme-credits.json):
`{ "remaining": 12.40, "limit": 50 }` → **$12.40 left of $50.00**.

For more shapes, the built-in providers are written the same way:
[vercel-gateway.json](../../../../Modules/Providers/Resources/Providers/vercel-gateway.json)
(a balance), [cline.json](../../../../Modules/Providers/Resources/Providers/cline.json),
and every file beside them.

## Sharing

On a custom provider's card, **Export…** saves its JSON without your key — the
key stays in your Keychain. Whoever imports it sees where it sends their key
before saving, and types their own.

## When it doesn't show up

- **Import says it can't read the file:** the JSON doesn't parse, or a required
  part is missing (`profile`, a data source, the `defaultDataSource` it names).
  The message says what is wrong.
- **No key field in Settings:** the `credential` must name the setting
  (`{ "setting": "apiKey" }`), and the setting must be `"kind": "secret"`.
- **Test Connection fails:** check the URL and header with `curl` first; then
  check each `at` and percent path against the real answer.
- **The id is taken:** a built-in's id can't be reused; Import gives yours a new
  one.

Every example in this guide is read by ClaudeBar's tests
(`CustomProviderGuideTests`), so it stays valid as the format grows.
