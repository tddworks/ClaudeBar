---
description: How ClaudeBar's docs are layered (Skill-style progressive disclosure), where each kind of content lives, and the limits CI checks. Read before adding or restructuring any doc.
---

# Documentation Design

> Status: **adopted**, 2026-09-24. CI fails when `scripts/check-docs.py --strict` reports a problem or the generated `docs/README.md` is stale.
> Adapted from baguette's documentation design; the differences are called out in [Decisions](#decisions).

## Goal

**Reduce accidental complexity so docs are easy to change.**

Every other rule follows from that goal. Each fact has exactly one home, so a code change touches at most one doc. When choosing between two options, pick the one where *the next change touches fewer places*.

## Problem

| File | Today | Accidental complexity |
|---|---|---|
| `CLAUDE.md` (now `AGENTS.md`) | 370 lines, ~14k chars, loaded every session | Repeats `docs/architecture/ARCHITECTURE.md` (layers, patterns, ISP hierarchy), copies the code (repository protocol tree, theme file tree, asset tree), and carries the release process and a user-facing logging guide. Already drifted: the overview names 13 providers where `Sources/Domain/Provider/` has 20, and it says credentials "remain in UserDefaults" while `KeychainCredentialRepository` exists |
| `README.md` | 483 lines | A 22-row provider list, five provider setup guides in `<details>`, Touch Bar, notch, Notify!, URL schemes, build, architecture, releasing and theme import. A "Multiple Providers in the Menu Bar" section landed after Contributors, just above License |
| Provider docs | none | Setup for 5 of 20 providers lives in the README. Probe research (RPC fields, endpoints, CLI screen quirks, why a fallback exists) lives in commit messages, PR bodies, code comments and `docs/plans/` |
| `docs/` | ~6.5k lines, no index | `architecture/`, `features/`, `plans/`, `release/`, `touchbar/` side by side; feature docs are flat files, except `extensions/` and `multi-account/` which are also folders |
| `CHANGELOG.md` | 1,155 lines, 89 releases | Healthier than baguette's: bullets average 145 chars. 37 are over 300, and some name internal types. Bullets are shown to users in Sparkle's update dialog, so they matter more than they look |
| Links | 7 broken | Four skills and `ARCHITECTURE.md` still point at `docs/ARCHITECTURE.md`, which moved to `docs/architecture/`. Nothing checks links |

**Root cause:** every provider copies the same facts into several places (README list + README setup guide + `CLAUDE.md` overview + `CLAUDE.md` repository table + `docs/index.html` + skills). Copies are synced by hand and nothing checks that they are.

## Principle: docs load like Skills

Agent Skills stay cheap by loading content in three tiers, where each tier only *points* to the next:

| Skill tier | Loaded | ClaudeBar docs equivalent |
|---|---|---|
| **1. Metadata** (`name` + `description`) | Always | `README.md`, `AGENTS.md`, the generated `docs/README.md` index, CHANGELOG lines |
| **2. Instructions** (`SKILL.md` body) | When needed | `docs/providers/<id>/README.md` and `docs/features/<x>/README.md`: set up or use one thing |
| **3. Resources** (`references/`, `scripts/`) | On demand, by link | `design.md` next to each README, `docs/architecture/*`, `docs/troubleshooting.md`, `docs/settings.md` |

Rules:

1. **One home per fact; tiers link, they don't copy.** Any copy is a future inconsistency.
2. **Don't write what the code already says.** File trees, protocol hierarchies and type lists are read from the source. A doc can't go stale about something it doesn't contain.
3. **Do write what the code can't say.** ClaudeBar reads quota from CLIs, private endpoints and local files that it doesn't own. *Why* a probe parses a screen this way, which field was renamed in which CLI version, and which fallback exists for what — that was found by experiment and is lost if it isn't written down. That research has a home: the provider's `design.md`.
4. **Same shape everywhere; nothing empty.** Every provider and feature gets the same folder shape, but no empty subfolders and no metadata fields nothing reads.

## Layout

```
README.md                       tier 1: pitch, screenshot, install, provider table → links
AGENTS.md                       tier 1: agent rules only (TDD gate, layers, build/test, one-line gotchas → links)
CONTRIBUTING.md                 tier 1: build, test, Tuist caveats, where things go → links
CHANGELOG.md                    tier 1: one line per change, what the user sees
docs/
├── README.md                   tier 1: index, GENERATED from descriptions
├── documentation-design/       this design (README.md) + layout.md
├── architecture/               ARCHITECTURE, THEME_DESIGN, REPORT_DESIGN, USER_BEHAVIORS (the one home for layers and patterns)
├── troubleshooting.md          tier 3: logs, Console filters, common probe errors (moved from CLAUDE.md)
├── settings.md                 tier 3: settings.json namespaces and where credentials live (moved from CLAUDE.md)
├── release/                    maintainer-only: RELEASE_SETUP, SPARKLE_SETUP (unchanged)
├── providers/                  one folder per provider, shaped like a Skill
│   ├── claude/
│   │   ├── README.md           tier 2: setup, probe modes, permissions, gotchas (≤200 lines)
│   │   └── design.md           tier 3: endpoints, fields, CLI screen quirks, fallbacks, dead ends
│   └── kiro/
│       └── README.md           most small providers stop here
└── features/                   one folder per app feature, same shape
    ├── notch/
    ├── notify/
    ├── touch-bar/
    ├── extensions/
    ├── menu-bar/               multiple providers, duration display, countdown colon
    ├── themes/                 built-in themes, terminal theme import
    ├── status-colors/
    ├── url-schemes/
    ├── session-hooks/
    ├── daily-usage/
    └── multi-account/
```

Outside this design and left alone: the website (`docs/index.html`), **`docs/appcast.xml`** (Sparkle reads it from that URL; moving it breaks auto-update for every installed copy), `docs/mockups/`, `docs/screenshots/`, `docs/sponsors/` and the HTML design pages under `docs/features/multi-account/`. They are pages or assets, not docs, and `check-docs` skips them.

File-by-file detail, written from the reader's side with a mockup of each file: [layout.md](layout.md).

Every provider and feature is a folder with a `README.md`, the same way every skill is a folder with a `SKILL.md`:

- **One predictable path.** A provider's docs are always at `docs/providers/<id>/`, where `<id>` is the provider's `id` in code (`claude`, `codex`, `zai`…). Readers and agents never guess.
- **Growing never moves anything.** Research becomes `design.md`, a deep dive becomes `<topic>.md`, both next to `README.md`.
- **GitHub shows it on open.** Browsing `docs/providers/codex/` renders the README.

## Tier 1: metadata

### Frontmatter: one field

```yaml
---
description: Track Codex 5-hour and weekly limits through the codex app-server RPC or the ChatGPT backend API. Use when Codex shows "—" or stale numbers.
---
```

- `description` works like a Skill's: one sentence saying *what* and *when*, ≤250 chars.
- No `name` field; the folder name is the name. No other fields until something reads them.
- `scripts/gen-docs.py` builds `docs/README.md` from these lines. Adding a provider's docs means writing one file.

### README.md (≤150 lines)

Keeps: logo/badges, one-paragraph pitch, screenshot, install (Homebrew, download, build-from-source pointer), a short "first run", the **provider table** (one row per provider: name, what it tracks, → its doc), a feature table (→ each feature doc), **Sponsors**, **Contributors**, license.

**Sponsors use the asc-cli format**: "Apps that use and support ClaudeBar development:" followed by one linked icon + name per app, then the GitHub Sponsors companies. One short block, no marketing copy; the tiers and pitch live in `SPONSORS.md`.

**Contributors stays in the README, in full.** It's how the project thanks people, and GitHub visitors expect it there. The table between `<!-- ALL-CONTRIBUTORS-LIST:START -->` and `<!-- ALL-CONTRIBUTORS-LIST:END -->` is generated by `scripts/sync-contributors.py` (~63 lines today and growing with every contributor), so it is excluded from the line budget, the same way generated files are. Everything else in the README counts.

| Section today | New home |
|---|---|
| Requirements → provider list | Provider table, one row each → `docs/providers/<id>/README.md` |
| Provider Setup Guides (`<details>`) | `docs/providers/<id>/README.md` |
| Quota Thresholds & Color Coding | `docs/features/status-colors/README.md` |
| Touch Bar Integration | `docs/features/touch-bar/README.md` |
| MacBook Notch Live Activity | `docs/features/notch/README.md` |
| Notify! Setup | `docs/features/notify/README.md` |
| URL Schemes | `docs/features/url-schemes/README.md` |
| Import Terminal Theme | `docs/features/themes/README.md` |
| User Extensions | `docs/features/extensions/README.md` |
| Multiple Providers in the Menu Bar | `docs/features/menu-bar/README.md` |
| Development, Build & Test, SwiftUI Previews | `CONTRIBUTING.md` |
| Architecture, Key Design Decisions | `docs/architecture/ARCHITECTURE.md` (already there) |
| Adding a New AI Provider | `CONTRIBUTING.md` → `add-provider` skill |
| Releasing | `docs/release/RELEASE_SETUP.md` |
| Dependencies | Deleted; `Tuist/Package.swift` is the list |

### AGENTS.md (≤100 lines, ≤12k chars)

The one agent-instructions file. There is no `CLAUDE.md`: Claude Code reads `AGENTS.md` natively when a project has no `CLAUDE.md` (v2.1.277+), and every other agent contributors use reads it too. Two files would drift, the way `CLAUDE.md` already drifted from the code. Older Claude Code, or Bedrock / Vertex sessions without native support, can add an untracked local `CLAUDE.md` containing `@AGENTS.md`.

Keeps: build/test commands (with the Tuist caching caveat), the three-layer rule, Chicago-school TDD and `@Mockable`, "no ViewModel", logging privacy (never log tokens), and **one line per gotcha** with a link.

- **Moves to `docs/architecture/ARCHITECTURE.md`**: the repository protocol hierarchy, settings storage design, key patterns. It already has most of them; `AGENTS.md` keeps one line each.
- **Moves to the `add-provider` skill**: the "Adding a New AI Provider" walkthrough and the provider → repository-type table.
- **Moves to `docs/troubleshooting.md`**: log locations, `log show` filters, common probe error strings.
- **Moves to `docs/release/`**: versioning and release steps.
- **Deleted**: the theme file tree, asset tree, dependency list (the code is their home).
- **Budget in characters too.** A line budget alone lets a 2,000-char line through.

### CHANGELOG.md

`scripts/extract-changelog.sh` copies a release's section into the GitHub release **and Sparkle's "What's new" dialog**. So the reader is a user deciding whether to click *Install Update*. Their questions, in order: *will this break me → is my bug fixed → what's new*.

- `Removed` / `Changed` come before `Fixed` and `Added`; anything that changes existing behaviour starts with `Breaking:` and says what to do instead.
- Each bullet starts with what the user sees or touches (a provider name, a Settings pane, the menu bar, the notch), says the effect rather than the implementation, and is ≤300 chars (URLs excluded). Related fixes are merged.
- Every bullet ends with its issue or PR link. **Links are absolute URLs**: relative links don't resolve in Sparkle's dialog or the GitHub release page. A bullet that changes how you use something may add `→ [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/…)`.
- Type names, file paths and probe internals go in the PR and the provider's `design.md`, never in the bullet.
- **History is kept in place.** Old entries keep their wording; see [Decisions](#decisions).

## Tier 2: provider or feature doc (≤200 lines)

Written for someone *using* it, human or agent. Contains only what the Settings UI and the code can't say:

1. **Title + one-line summary**: what is tracked (5-hour window, weekly, credits, spend)
2. **Setup**: what to install or sign in to, and where in Settings to turn it on
3. **Probe modes**: when there are several (CLI / API / RPC / cookie), which to pick and what each needs
4. **Permissions**: Full Disk Access, Keychain prompts, folder-trust prompts, and why they're asked
5. **Gotchas**: what will bite a user, e.g. "the key must be in the Claude config, not only your shell", "Antigravity quota needs a stored sign-in when the app is closed"
6. **See also**: `design.md`, `docs/troubleshooting.md#<provider>`, related providers

No type lists, no file maps, no test snippets, no settings-key tables (those are in `docs/settings.md`).

## Tier 3: resources

- **`docs/providers/<id>/design.md`**: contributor-facing research for one provider. The endpoints or CLI invocations, the response fields that matter (with the CLI/API version they were seen in), the screen-scraping rules, the fallback chain and why each step exists, what was tried and failed. Today's `docs/plans/2026-01-22-bedrock-provider-design.md` and `2026-02-04-codex-api-probe-design.md` move here; so does future research like the Codex `resetsAt` and Antigravity empty-`pgrep` findings.
- **`docs/features/<x>/design.md`**: the same for app features (notch, notify, reports). Today's `docs/plans/2026-06-09-daily-usage-dedup-design.md` becomes `features/daily-usage/design.md`.
- **`docs/architecture/`**: the one home for layers, patterns, data flow, the theme and report systems.
- **`docs/troubleshooting.md`**: log files, OSLog filters, what each common probe error means. Provider-specific errors stay in that provider's Gotchas and are linked from here.
- **`docs/settings.md`**: `settings.json` namespaces and where secrets live (Keychain vs settings file). One home, linked from provider docs.
- **Deleted, not moved**: file trees, protocol trees, type lists, dependency lists.

## Reader paths

| Reader | Path |
|---|---|
| New user | README → install → provider table |
| Setting up a provider | README provider table → `docs/providers/<id>/README.md` |
| Provider shows an error | Popover error → `docs/troubleshooting.md` → provider Gotchas |
| Upgrading | Sparkle dialog / CHANGELOG line → linked issue or doc |
| Extension author | `docs/features/extensions/README.md` |
| Contributor | CONTRIBUTING → `docs/architecture/ARCHITECTURE.md` → provider `design.md` → code |
| Agent fixing a bug | AGENTS.md → `fix-bug` skill → provider `design.md` |
| Agent adding a provider | AGENTS.md → `add-provider` skill → a similar provider's `design.md` |

## Update rules

| Change | Touch | Nothing else |
|---|---|---|
| New provider | `docs/providers/<id>/README.md` with a `description`, one README table row, one CHANGELOG line, `make docs` | |
| Probe changes (new field, new fallback, CLI output changed) | The provider's `design.md`; its Gotchas if users could hit it | |
| New setting | `docs/settings.md` if it adds a namespace; the provider or feature README if users must set it | |
| New feature | `docs/features/<x>/README.md`, one CHANGELOG line, a README feature-table row | |
| Bug fix | One CHANGELOG line; a Gotchas entry if users could hit it again | |
| New agent-wide rule | One line in `AGENTS.md`, linking to where it's explained | |

Skills follow the same rule: `.claude/skills/*` carry agent workflows and link to docs rather than restate them.

## Enforcement

`scripts/check-docs.py --strict`, run in CI by `.github/workflows/docs.yml`. Kept small, because it is code that also has to be maintained.

| Check | Limit |
|---|---|
| Line budgets | README ≤150 (the generated all-contributors block excluded), AGENTS.md ≤100, `docs/{providers,features}/*/README.md` ≤200 |
| Char budget | AGENTS.md ≤12,000 |
| CHANGELOG bullet length in `[Unreleased]` | ≤300 chars, URLs excluded |
| CHANGELOG links in `[Unreleased]` | absolute URLs only (Sparkle can't resolve relative ones) |
| Every provider / feature README has a `description` | required, ≤250 chars |
| Every provider in `Sources/Domain/Provider/` has `docs/providers/<id>/README.md` | required |
| Relative links resolve (code fences and inline code skipped) | all `.md` files |
| Generated `docs/README.md` is current | `gen-docs.py`, then `git diff --exit-code` |

When a doc goes over budget, split it. Don't raise the limit.

## Migration

Done in one PR (#307), one commit per step, and the docs stayed valid after each one.

1. **Hygiene**: this design; `git mv CLAUDE.md AGENTS.md` and fix its drift (provider count, credential storage, the stale repository table); fix the 7 broken links; README Sponsors in the asc-cli format; `scripts/check-docs.py` in report-only mode.
2. **Move features**: `git mv` each `docs/features/<x>.md` to `docs/features/<x>/README.md`, `docs/touchbar/` to `docs/features/touch-bar/`, `docs/plans/*` to the owning `design.md`; a script rewrites links and `check-docs.py` proves none broke. Mechanical, no content changes.
3. **Generation**: `scripts/gen-docs.py` builds `docs/README.md`; add `description` to each doc.
4. **Providers**: one `docs/providers/<id>/README.md` per provider, starting from the README's setup guides; `design.md` where research exists. Parallelisable per provider.
5. **Tier 1**: slim README; add `CONTRIBUTING.md`, `docs/troubleshooting.md`, `docs/settings.md`; slim `AGENTS.md` to its budget; move walkthroughs into skills.
6. **Enforce**: turn `check-docs.py --strict` on in CI.

## Decisions

Each one is judged by the goal: *does the next change touch fewer places?*

| Question | Decision | Why |
|---|---|---|
| Unit of docs | **Provider first, then feature** | 20 of ClaudeBar's facts-that-drift are per provider; features are the minority |
| Generated command reference | **None** | ClaudeBar is a GUI app; there's no `--help` to generate from. The Settings UI is the "flags" and is self-describing |
| Probe research | **Move to the provider's `design.md`**, don't delete | It records experiments against CLIs and endpoints ClaudeBar doesn't own, which the code can't explain and nobody wants to redo |
| `docs/plans/` | **Move into the owning `design.md`** | A dated plan is research about one provider or feature; filed by date, nobody finds it from the feature |
| File trees, protocol trees, type lists | **Delete** | They copy the code, so every refactor would need a doc edit nobody makes |
| `CLAUDE.md` vs `AGENTS.md` | **`AGENTS.md` only** | Contributors use several agents and every one reads it, Claude Code included (v2.1.277+). One file can't drift from a second. Sessions without native support can add a local, untracked `CLAUDE.md` containing `@AGENTS.md` |
| CHANGELOG size | **Keep history in place; enforce style on `[Unreleased]` only** | baguette rolls off by minor, but ~70 of ClaudeBar's 89 releases are 0.4.x, so a minor rollover wouldn't shrink the file. Bullets are already short on average; rewriting history is work with no gain |
| CHANGELOG links | **Absolute URLs** | The same text renders in Sparkle's dialog and GitHub releases, where relative links break |
| Contributors in the README | **Keep, in full; the generated block doesn't count toward the budget** | It's generated by `sync-contributors.py`, so it costs no manual edits; moving it would hide the thanks for no gain in maintainability |
| Frontmatter fields | **`description` only** | Every extra field has to be kept correct |
| Hand-written vs generated index | **Generated** | Adding a provider touches one file instead of two |
| Website, appcast, mockups under `docs/` | **Out of scope** | Pages and a live update feed, not docs; moving them breaks the site or auto-update |
