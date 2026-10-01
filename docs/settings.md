---
description: What's in ~/.claudebar/settings.json, one example per namespace, and where tokens and API keys are stored instead (Keychain or the app's credential store). Use when editing settings by hand or adding a setting.
---

# Settings File

Everything you set in the Settings window is saved to one JSON file:

```
~/.claudebar/settings.json
```

Secrets are the exception: API keys and tokens never go in this file. See [where secrets live](#where-secrets-live).

## Format

Keys are written with dots in code (`app.themeMode`), and each dot is one level of nesting in the file:

```json
{
  "app": { "themeMode": "system" },
  "providers": { "claude": { "isEnabled": true } }
}
```

A key that's missing means "use the default", so a fresh install starts with an almost empty file. Keys ClaudeBar doesn't recognize are kept when it saves.

## Namespaces

| Namespace | Holds | Example |
|---|---|---|
| `app.*` | App-wide preferences: theme, menu bar readout, refresh, burn rate, status colors, notch, Touch Bar | `"app": { "burnRateWarningEnabled": true, "burnRateThreshold": 1.5 }` |
| `providers.<id>.*` | Per-provider switches, keyed by the provider id | `"providers": { "gemini": { "isEnabled": false } }` |
| `<provider>.*` | Settings only one provider has: probe mode, env var name, region, config path | `"codex": { "probeMode": "rpc" }` |
| `hook.*` | [Session hooks](features/session-hooks/README.md) | `"hook": { "enabled": true }` |
| `notify.*` | [Notify!](features/notify/README.md) device link and surfaces | `"notify": { "enabled": true, "widgetEnabled": true }` |
| `extensions.<extension-id>.*` | Non-secret fields of a user [extension](features/extensions/README.md)'s config | `"extensions": { "my-api": { "baseURL": "https://…" } }` |

Provider ids are the folder names under [providers/](providers/) (`claude`, `codex`, `zai`, `opencode-go`…). Provider namespaces in use today: `alibaba`, `bedrock`, `claude`, `codex`, `copilot`, `deepseek`, `kimi`, `minimax`, `vercel`, `zai`.

A few `app.*` keys worth knowing:

| Key | Values |
|---|---|
| `app.themeMode` | `system` (default), `light`, `dark`, `cli`, `christmas`, or `imported-<name>` |
| `app.usageDisplayMode` | `remaining` (default), `used`, `pace` |
| `app.menuBarProviderSettings` | Per-provider menu bar choices: `{ "codex": { "primaryQuotaKey": "session", "secondaryQuotaKey": "weekly", "stacked": false, "stackedSize": "small" } }` |
| `app.statusColorOverrides` | `{ "warning": "#F2BF33" }`; only the levels you set |

The full list is the code: every key is read and written in [`JSONSettingsRepository.swift`](../Sources/Infrastructure/Storage/JSONSettingsRepository.swift), and extension fields in [`JSONExtensionConfigStore.swift`](../Sources/Infrastructure/Extension/JSONExtensionConfigStore.swift).

## Editing by hand

1. **Quit ClaudeBar first.** It loads app-wide settings once at launch and writes them back when they change, so an edit made while it runs can be lost or ignored.
2. Keep the file valid JSON. **If it doesn't parse, ClaudeBar treats it as empty**, and the next setting you change rewrites the file with only that one key. Keep a copy before editing.
3. Relaunch.

Deleting the file resets every setting to its default. Secrets stay where they are.

## Where secrets live

| Secret | Stored in |
|---|---|
| Vercel AI Gateway API key | Keychain |
| Notify! device token | Keychain, or the app credential store on builds the Keychain refuses (see below) |
| GitHub token and username (Copilot) | App credential store |
| MiniMax, DeepSeek and Alibaba API keys, Alibaba manual cookie | App credential store |
| Secret fields of user extensions | App credential store |
| Your provider sign-ins (Claude Code, Codex, Gemini, Grok, Cursor…) | Where that provider's own CLI or app keeps them. ClaudeBar reads them there; see each [provider doc](providers/) |

- **Keychain** items are generic passwords under the service `com.tddworks.claudebar.credentials`, readable only after first unlock. Look them up in Keychain Access.
- **The app credential store** is ClaudeBar's own macOS preferences (`defaults read com.tddworks.claudebar`), with keys starting `com.claudebar.credentials.`. It isn't encrypted beyond your account's normal file protection. Moving these secrets to the Keychain is planned. The Vercel key has already moved: an old copy found there is moved to the Keychain the first time it's read.
- **Environment variables**: some providers take a key from an env var instead (`zai.glmAuthEnvVar`, `copilot.authEnvVar`, `minimax.authEnvVar`…). The settings file stores only the variable's *name*, never its value.
- **Ad-hoc signed builds** (ones you compile yourself) can't use the Keychain, so the Notify! token falls back to the app credential store and the Notify! pane says so. A Developer ID build from the release page isn't affected.

## See also

[Troubleshooting](troubleshooting.md) · [ARCHITECTURE.md](architecture/ARCHITECTURE.md) for how the settings repositories are split per provider
