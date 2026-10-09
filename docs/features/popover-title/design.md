# Popover Title — design

> Applies [the design](../../architecture/ARCHITECTURE.md) to the popover's
> header title. Users: [README.md](README.md). It is the page's, like a
> [status colour](../status-colors/design.md): no provider, login or quota is
> involved, so nothing in the canonical tree changes.

## The person and the moment

Someone who shares their screen, keeps the menu bar on a team machine, or
just likes their tools named their way opens the popover and wants it to say
*their* name, not the product's. The product's name stays where the product
speaks for itself (About, the Settings sidebar).

## The words

| Word | Means |
|---|---|
| **popover title** | the big line in the popover header, above the tagline. Default *ClaudeBar* |
| **tagline** | the line under it (*AI Usage Monitor*, or a theme's own) — not part of this feature |

## Pieces

| Piece | Where | One job |
|---|---|---|
| `PopoverTitle` | `Sources/Domain/Settings/PopoverTitle.swift` | a value: turns what the person typed into what the header shows (`shown`) and says whether it is the default (`isDefault`) |
| `AppSettingsRepository.popoverTitle()` / `setPopoverTitle(_:)` | Domain port, `JSONSettingsRepository` | keeps the raw text at `app.popoverTitle`, `""` when never set |
| `AppSettings.popoverTitle` | `Sources/App/Settings/AppSettings.swift` | the observed setting; writes through on change |
| Header | `MenuContentView` | renders `settings.popoverTitle.shown` — never trims, counts or compares |
| *Popover Title* row | `AppearancePane` | a `SettingsTextField` (placeholder *ClaudeBar*) and *Reset*, shown when not default |

```
 Appearance pane ──types──▶ AppSettings.popoverTitle ──set──▶ JSONSettingsRepository
                                     │                          (app.popoverTitle)
                                     ▼
                         PopoverTitle(raw).shown ──▶ MenuContentView header
```

## Laws

| Law | Owner |
|---|---|
| a blank title (empty or only whitespace) shows *ClaudeBar* | `PopoverTitle` |
| the title is one line: line breaks become spaces, at most 24 characters, and no whitespace around it | `PopoverTitle` |
| what the person typed is stored as typed; the rule applies when shown, so a newer rule never rewrites the file | `PopoverTitle` · `JSONSettingsRepository` |
| only the popover header shows it; the product's own places (About, Settings sidebar, accessibility label, Touch Bar) keep *ClaudeBar* | `MenuContentView` |

## Tests

- Domain: `PopoverTitleTests` — blank → *ClaudeBar*, trims, joins lines, caps at 24, `isDefault`.
- Infrastructure: `JSONSettingsRepositoryAppTests` — `""` when unset, round-trips the raw text.
