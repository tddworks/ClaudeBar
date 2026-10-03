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
| `providers.order` | Your provider display order — the popover pills, the overview and ⌘1–⌘9 follow it; unset means registration order | `"providers": { "order": ["codex", "claude"] }` |
| `providers.<id>.cliPath` | The *CLI location* a person chose for a provider that runs a CLI; absent means "find it as usual" (#210) | `"providers": { "claude": { "cliPath": "/opt/tools/bin/claude" } }` |
| `providers.<id>.hiddenQuotaKeys` | Quotas a person stopped watching for a product, by quota key (`model:gemini-2.0-flash`); shared by its accounts. A key no longer reported is ignored, and hiding every quota hides none (#140) | `"providers": { "gemini": { "hiddenQuotaKeys": ["model:gemini-2.0-flash"] } }` |
| `<provider>.*` | A provider's own settings, each named in its definition's `settings` (`<id>.<setting>`), and its data source choice (`<id>.probeMode`) | `"kimi": { "probeMode": "api", "region": "international" }` |
| `hook.*` | [Session hooks](features/session-hooks/README.md) | `"hook": { "enabled": true }` |
| `alerts.*` | [Quota alerts](features/quota-alerts/README.md): the percentages you chose | `"alerts": { "thresholds": [60, 35] }` |
| `notify.*` | [Notify!](features/notify/README.md) device link and surfaces | `"notify": { "enabled": true, "widgetEnabled": true }` |
| `ext-<extension-id>.*` | A user [extension](features/extensions/README.md)'s non-secret config fields, as provider settings. Values an older version kept under `extensions.<extension-id>.*` move here once | `"ext-my-api": { "baseURL": "https://…" }` |

Provider ids are the folder names under [providers/](providers/) (`claude`, `codex`, `zai`, `opencode-go`…). A provider's settings are listed in its definition, `Modules/Providers/Resources/Providers/<id>.json`; an added account's own values are kept with that account. A value an older version saved under another key, or as a number or a list, is still read, and moves to `<id>.<setting>` the first time it's saved.

A few `app.*` keys worth knowing:

| Key | Values |
|---|---|
| `app.themeMode` | `system` (default), `light`, `dark`, `cli`, `christmas`, `pop`, `platformer`, or `imported-<name>` |
| `app.themeTextStyle` | `themed` (default: a theme's own face on every word) or `classic` (the theme's look in normal fonts). Only Platformer offers the choice |
| `app.themeRunner` | `true` (default) puts a theme's runner on its floor; `false` takes it and its lane away. Only Platformer has a runner |
| `app.usageDisplayMode` | `remaining` (default), `used`, `pace` |
| `app.menuBarProviderLogoEnabled` | `false` (default) shows a single readout without a logo; `true` starts it with the provider's logo. Several providers or accounts always show logos |
| `app.menuBarAccountLabelsEnabled` | `true` (default) shows names when the same provider has multiple enabled accounts; `false` hides those names. Single accounts never show an account name in either mode |
| `app.hideAccountEmail` | `false` (default) shows account emails; `true` masks them as `s•••@g•••.com` in the menu bar, its tooltip and the popover. The eye beside the account toggles it ([#375](https://github.com/tddworks/ClaudeBar/issues/375)) |
| `app.popoverTextSize` | `medium` (default), `large`, `extraLarge` — scales the popover's text up to 1.4× and widens the window to fit. No smaller step is offered: the popover's smallest labels are already 8pt |
| `app.menuBarProviderSettings` | Per-provider menu bar choices: `{ "codex": { "primaryQuotaKey": "session", "secondaryQuotaKey": "weekly", "stacked": false, "stackedSize": "small" } }` |
| `app.nativeMenuBarIconsEnabled` | `false` (default) keeps brand colors; `true` uses monochrome provider marks for every menu bar account, adapting to the bar’s appearance |
| `app.statusColorOverrides` | `{ "warning": "#F2BF33" }`; only the levels you set |

The full list is the code: app-wide keys are read and written in [`JSONSettingsRepository.swift`](../Sources/Infrastructure/Storage/JSONSettingsRepository.swift), and provider keys, extensions' included, come from each definition's `settings` (an extension's config is read as one in [`Extensions.swift`](../Modules/Providers/Sources/Extensions.swift)).

## Editing by hand

1. **Quit ClaudeBar first.** It loads app-wide settings once at launch and writes them back when they change, so an edit made while it runs can be lost or ignored.
2. Keep the file valid JSON. **If it doesn't parse, ClaudeBar treats it as empty**, and the next setting you change rewrites the file with only that one key. Keep a copy before editing.
3. Relaunch.

Deleting the file resets every setting to its default. Secrets stay where they are.

## Where secrets live

| Secret | Stored in |
|---|---|
| Provider keys you paste into ClaudeBar — API keys, tokens, session cookies, for the default login and every added account | Keychain (the provider vault). A key an older version kept in the app credential store moves to the Keychain after a verified write, the first time it's read |
| Notify! device token | Keychain, or the app credential store on builds the Keychain refuses (see below) |
| Secret fields of user extensions | Keychain (the provider vault). One an older version kept in the app credential store moves there once |
| Your provider sign-ins (Claude Code, Codex, Gemini, Grok, Cursor…) | Where that provider's own CLI or app keeps them. ClaudeBar reads them there; see each [provider doc](providers/) |

- **Keychain** items are generic passwords under the service `com.tddworks.claudebar.credentials`, readable only after first unlock. Look them up in Keychain Access.
- **The app credential store** is ClaudeBar's own macOS preferences (`defaults read com.tddworks.claudebar`), with keys starting `com.claudebar.credentials.`. It isn't encrypted beyond your account's normal file protection. Provider and extension keys left there by older versions move to the Keychain.
- **Environment variables**: some providers take a key from an env var instead (`zai.glmAuthEnvVar`, `copilot.authEnvVar`, `minimax.authEnvVar`…). The settings file stores only the variable's *name*, never its value.
- **Another tool's login** (the GitHub CLI's, Antigravity's, Claude Code's) is read from that tool's own Keychain item or file and never written by ClaudeBar, except where the provider's doc says it renews a token there.
- **Ad-hoc signed builds** (ones you compile yourself) can't use the Keychain, so the Notify! token falls back to the app credential store and the Notify! pane says so. A Developer ID build from the release page isn't affected.

## See also

[Troubleshooting](troubleshooting.md) · [ENGINE_DESIGN §2.2](architecture/ENGINE_DESIGN.md#22--settings-one-form-two-scopes) for how a provider's settings form is read and kept


## Additional Codex accounts

`providers.codex.accounts` stores `ProviderAccountConfig` entries: an opaque local
`accountId`, empty `label`, login `email`, and `probeConfig.codexHome` plus
`probeConfig.chatgptAccountId`. Tokens remain in that Codex home's `auth.json`.
Instances use `codex.<accountId>` for enabled state and menu bar selection/settings;
the original account keeps `codex`. `codex.probeMode` remains shared.
Removing an account deletes its entry and menu bar selection, not its Codex files.
