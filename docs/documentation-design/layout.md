---
description: File-by-file detail of ClaudeBar's documentation layout, written from the reader's side. For each file, who opens it, the question they bring, a mockup, and what stays out.
---

# Layout in Detail

This is the companion to [the design](README.md). Each file below is described from the **reader's side**: who opens it, what question they have, and what they should see. Anything that doesn't answer that question belongs in a different file.

## Which file answers my question?

| I am… | …and I want to know | I open |
|---|---|---|
| Evaluating the app | What is this? Does it track the tools I use? | `README.md` |
| Deciding whether to update | What changed? Is my bug fixed? | Sparkle's dialog, which shows the `CHANGELOG.md` section |
| Setting up a provider | What do I install or sign in to, and which mode do I pick? | `docs/providers/<id>/README.md` |
| Looking at an error in the popover | What does this mean and how do I fix it? | `docs/troubleshooting.md` → the provider's Gotchas |
| Using a feature | How do I turn on the notch, Notify!, the Touch Bar, or extensions? | `docs/features/<x>/README.md` |
| Looking for anything | Is it documented, and where? | `docs/README.md` |
| Writing an extension | What does the manifest look like and what must the script print? | `docs/features/extensions/README.md` |
| Contributing | How do I build, test, and where does code go? | `CONTRIBUTING.md` → `docs/architecture/ARCHITECTURE.md` |
| Changing a probe | Why does it parse this way, and what already failed? | `docs/providers/<id>/design.md` |
| An agent working in this repo | What must I always or never do? | `AGENTS.md` |

---

## `CHANGELOG.md`

**Who:** a user looking at Sparkle's "A new version is available" dialog, a user on the GitHub releases page, or someone checking whether their issue is fixed. `scripts/extract-changelog.sh` copies the release's section into both places.

**Their questions, in order:**
1. **Will this break me?** A setting that moved, a mode that was removed, a permission that is now needed.
2. **Is my bug fixed?** They skim for the provider or screen they use.
3. **What's new that I could use?**
4. **Where do I learn more?** One link.

They don't care which probe class, RPC field or repository protocol changed. That belongs to reviewers, and it lives in the PR and the provider's `design.md`.

### Rules

| Rule | Why (reader's view) |
|---|---|
| Keep a Changelog headings; **`Removed` and `Changed` come before `Fixed` and `Added`** | Question 1 is answered first |
| Anything that changes existing behaviour starts with **`Breaking:`** and says what to do instead | Users can spot it in a dialog they read for five seconds |
| Each bullet starts with **what the user sees**: a provider name, a Settings pane, the menu bar, the notch | They are scanning for *their* provider |
| Say the **effect**, not the implementation: "Codex's menu bar countdown ticks down", not "`CodexRateLimitWindow` carries `resetsAt`" | They can check the effect but not the implementation |
| One bullet per user-visible change, **≤300 chars** with URLs excluded; merge related fixes | Five bullets about one provider are one piece of news |
| Every bullet ends with its issue or PR link as an **absolute URL** | Relative links break in Sparkle's dialog and on the release page |
| `## [Unreleased]` is always at the top, and the release workflow renames it | One edit per release, done by CI |

### Before → after (real entries)

**Before ([Unreleased], #298):**

> - Codex's menu bar countdown now matches the other providers ("2:33", "2d") and ticks down with the clock. The Codex RPC probe used to keep only the formatted "Resets in 4h 42m" text and throw away the reset time, so the menu bar showed a frozen countdown in a different format, and pace-aware status and burn rate couldn't work for Codex. The reset time and window length are now passed through. ([#298](https://github.com/tddworks/ClaudeBar/issues/298))

This is about 420 characters. The second half explains the probe, and that belongs in the PR.

**After:**

```markdown
### Fixed
- Codex: the menu bar countdown now ticks and matches the other providers ("2:33", "2d"), and pace-aware colors work for Codex. ([#298](https://github.com/tddworks/ClaudeBar/issues/298))
```

The detail about the formatted text and the thrown-away reset time moves to `docs/providers/codex/design.md`, which becomes its one home.

**Old entries** keep their wording and stay where they are.

---

## `README.md` (≤150 lines, contributors table excluded)

**Who:** someone who found the repo through a link, Homebrew, Reddit, or an agent's recommendation.
**Their question:** *What is this, does it track my tools, and how do I install it?*

```markdown
# ClaudeBar                                        ← logo + badges
Every AI coding quota in your menu bar: Claude, Codex, Gemini, Copilot
and 16 more, with alerts before you run out.      ← 2-line pitch

![screenshot]                                      ← one image or GIF

## Install                                         ← ~10 lines
brew install --cask claudebar
Or download the DMG · Build from source → CONTRIBUTING.md

## Providers                                       ← one row per provider, each → its doc
| Provider | Tracks | Setup |
| Claude | 5-hour, weekly, Opus/Sonnet/Fable limits | [docs](docs/providers/claude/README.md) |
| Codex | 5-hour and weekly limits | [docs](docs/providers/codex/README.md) |
| Z.ai | GLM Coding Plan quota | [docs](docs/providers/zai/README.md) |
…
| Your own | Any script via `~/.claudebar/extensions/` | [docs](docs/features/extensions/README.md) |

## Features                                        ← one row per feature, each → its doc
| Menu bar | Up to three providers, % or countdown | [docs](docs/features/menu-bar/README.md) |
| Notch | Live quota in the MacBook notch | [docs](docs/features/notch/README.md) |
| Notify! | Quota on your iPhone Lock and Home Screen | [docs](docs/features/notify/README.md) |
…

## More                                            ← links, nothing else
Docs index · Troubleshooting · Contributing · Changelog

## Sponsors                                      ← asc-cli format: "Apps that use and support ClaudeBar development:"
## Contributors                                    ← kept in full; generated block not counted
<!-- ALL-CONTRIBUTORS-LIST:START --> … <!-- ALL-CONTRIBUTORS-LIST:END -->
## License
```

**Not here:** the setup guides, URL schemes, the Touch Bar and notch walkthroughs, build commands, architecture, releasing, or the dependency list. Each has one home, listed in [the design](README.md#readmemd-150-lines).

---

## `docs/README.md` (generated)

**Who:** someone who knows what they want to do but not where it's written down.
**Their question:** *Is it documented, and where?*

`scripts/gen-docs.py` builds it from each provider and feature doc's `description`. It is never edited by hand, and CI fails if it's stale.

```markdown
# ClaudeBar docs
<!-- GENERATED by scripts/gen-docs.py from docs/{providers,features}/*/README.md frontmatter. Do not edit. -->

Start with the [README](../README.md). Something broken? See [troubleshooting](troubleshooting.md).

## Providers
| Provider | What it's for |
|---|---|
| [alibaba](providers/alibaba/README.md) | Track Alibaba Coding Plan 5-hour, weekly and monthly quotas… |
| [antigravity](providers/antigravity/README.md) | Track Antigravity model quotas, with or without the app open… |
…

## Features
| [extensions](features/extensions/README.md) | Add any quota source with a script and a manifest… |
…

Guides: [architecture](architecture/ARCHITECTURE.md) · [settings](settings.md) · [documentation design](documentation-design/README.md)
```

Sorted alphabetically within the two groups. The only grouping is the folder the doc is in, so there's no extra field to maintain.

---

## `docs/providers/<id>/README.md` (≤200 lines)

**Who:** a user, or an agent helping one, turning a provider on or fixing it.
**Their question:** *What do I need, which mode do I pick, and what will go wrong?*

`<id>` is the provider's `id` in code: `alibaba`, `ampcode`, `antigravity`, `bedrock`, `claude`, `codex`, `commandcode`, `copilot`, `cursor`, `deepseek`, `gemini`, `grok`, `kimi`, `kiro`, `minimax`, `mistral`, `omp`, `opencode-go`, `vercel-gateway`, `zai`.

Here's today's README `<details>` block for Kimi after the move:

````markdown
---
description: Track Kimi Code usage through the interactive kimi CLI or the Kimi web API. Use when setting up Kimi or when it shows "Authentication required".
---

# Kimi

Shows your Kimi Code usage windows and reset times.

## Setup
1. Install the Kimi Code CLI (`curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash`), then run `kimi` once and sign in.
2. Settings → Providers → Kimi → turn it on.

## Probe modes
| Mode | Needs | Pick it when |
|---|---|---|
| CLI (default) | `kimi` on your PATH | Almost always |
| API | Full Disk Access, a browser signed in to kimi.com | You don't want the CLI installed |

## Permissions
- API mode reads the browser's cookie store, which is why macOS asks for **Full Disk Access**. CLI mode needs nothing.

## Gotchas
- kimi CLI 0.36 changed the `/usage` layout; ClaudeBar reads both.

## See also
[design.md](design.md) · [troubleshooting](../../troubleshooting.md#kimi)
````

Most providers stop at this one file.

---

## `docs/providers/<id>/design.md`

**Who:** a contributor, or an agent following the `fix-bug` or `add-provider` skill, about to change how a probe reads quota.
**Their question:** *Why is it this way, and what has already failed?*

This is ClaudeBar's hard-won knowledge. It isn't in the code, because it's about other people's CLIs and endpoints. Each file holds:

- **The sources**: the CLI command, RPC method or endpoint for each probe mode, and the order the fallbacks run in.
- **The fields that matter**, with the version where each was seen, for example Codex `account/rateLimits/read` → `primary.resetsAt` (epoch seconds) and `windowDurationMins` (a weekly window showed up as the *primary* window in 2026-09).
- **Parsing rules and why**: screen scraping with the scrollback read, because `/usage` grew past 50 rows in Claude Code 2.1.170; dedup by `(message.id, requestId)`.
- **Dead ends**: what was tried and why it doesn't work, so nobody tries it again.
- **Known limits**, in full. `AGENTS.md` keeps one line that links here.

There's no line budget, because it's tier 3 and only read on demand. It still links instead of copying: settings keys are in `docs/settings.md`, and the layers are in `docs/architecture/`.

---

## `docs/features/<x>/README.md` and `design.md`

The same shape and budget as a provider, for app features: `menu-bar`, `notch`, `notify`, `touch-bar`, `extensions`, `themes`, `status-colors`, `url-schemes`, `session-hooks`, `daily-usage`, `multi-account`. The Touch Bar README looks like this after the move:

````markdown
---
description: Show quota gauges on a MacBook Pro Touch Bar, always visible without opening the menu. Use on Touch Bar Macs.
---

# Touch Bar

## Quick start
Settings → Touch Bar → Show quota on Touch Bar.

## Gotchas
- Only on MacBook Pro models with a Touch Bar; the setting is hidden elsewhere.
- Uses a private system-modal Touch Bar API; macOS updates can break it.

## See also
[design.md](design.md) — the persistent driver and why it's private API
````

---

## `docs/troubleshooting.md`

**Who:** a user whose provider shows an error, or a maintainer asking a reporter for logs.
**Their question:** *Where are the logs, and what does this error mean?*

It holds the log file path and rotation, "Settings → Open Logs Folder", the `log show` / `log stream` filters, and a table of common error strings. Each error has its meaning and a link to the provider Gotchas that explain the fix. This content moves out of `CLAUDE.md`, where only agents saw it.

## `docs/settings.md`

**Who:** a power user editing `~/.claudebar/settings.json`, or a contributor adding a setting.
**Their question:** *What's the key, and where is my token stored?*

It covers the namespaces (`app.*`, `providers.<id>.*`, `<provider>.*`, `hook.*`, `notify.*`) with one example each, and which secrets are in the Keychain rather than the file. It links to the code for the full list instead of copying every key.

## `docs/architecture/`

**Who:** a contributor asking *how does a refresh become a menu bar update?*

It's unchanged, and it's the one home for layers, the ISP repository design, data flow, and the theme and report systems. `AGENTS.md` and `CONTRIBUTING.md` link here instead of redrawing it.

## `CONTRIBUTING.md`

**Who:** a first-time contributor.
**Their question:** *How do I build, run the tests, and get a PR merged?*

```markdown
# Contributing
## Build & test            tuist install · tuist generate · tuist test (and why xcodebuild test bypasses the cache)
## How code is organised   3 lines + link to docs/architecture/ARCHITECTURE.md
## Adding a provider       → add-provider skill, and a similar provider's design.md
## Rules                   TDD first, Chicago school, no ViewModel (link to AGENTS.md)
## Docs                    the update-rules table, by link to docs/documentation-design/
## Releasing               → docs/release/RELEASE_SETUP.md (maintainers)
```

## `AGENTS.md` (≤100 lines, ≤12k chars)

**Who:** an AI agent at the start of *every* session in this repo.
**Its question:** *What must I always or never do here?*

```markdown
# AGENTS.md
## Build & test              ← tuist commands, xcodebuild to bypass the cache (~10 lines)
## Architecture              ← Domain / Infrastructure / App, QuotaMonitor is the source of truth,
                               no ViewModel, ISP settings sub-protocols → docs/architecture/ (~15 lines)
## TDD                       ← Chicago school, Swift Testing, @Mockable, state not calls (~8 lines)
## Logging                   ← AppLog categories; never log tokens (~5 lines)
## Gotchas                   ← one line each → design.md
- SourceKit "No such module" in the editor is expected; modules resolve at build time
- Codex RPC: keep resetsAt and windowDurationMins; the primary window can be weekly → providers/codex/design.md
- CLI probes run in a dedicated working directory so trust prompts don't block them → providers/claude/design.md
…
## When you are…             ← pointers, loaded only when relevant
- adding a provider  → add-provider skill
- fixing a bug       → fix-bug skill
- touching docs      → docs/documentation-design/
```

**Moved out:** the repository-protocol tree and settings storage (to `docs/architecture/`), the provider walkthrough (to the `add-provider` skill), logging for users (to `docs/troubleshooting.md`), and release steps (to `docs/release/`). The asset tree, theme file tree and dependency list are deleted.
