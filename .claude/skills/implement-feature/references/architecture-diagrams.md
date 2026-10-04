# Architecture Diagram Patterns

ASCII diagrams for the design review. Draw what the feature touches in the
**modules** ([MODULAR_DESIGN.md](../../../../docs/architecture/MODULAR_DESIGN.md)),
not in layers. Use the words of [CANONICAL_MODEL.md](../../../../docs/architecture/CANONICAL_MODEL.md):
Provider, DataSource, Fetch, Mapping, Usage, Quota, Plan, Cost.

## The module map

```
┌──────────────────────────────────────────────────────────────────────┐
│ ClaudeBar (App) — composition root: ClaudeBarApp, SwiftUI views       │
└──────────┬──────────────────────────────┬────────────────────────────┘
           │                              │
           ▼                              ▼
┌──────────────────────┐        ┌──────────────────────────────────────┐
│ Domain               │        │ Providers                            │
│ QuotaMonitor,        │──────▶ │ Provider (one lifecycle), Definition,│
│ extension providers, │        │ AddedAccounts, settings contracts    │
│ Notify!, sessions    │        │ Resources/Providers/<id>.json (+.js) │
└──────────────────────┘        └──────────────────┬───────────────────┘
                                                   ▼
                                ┌──────────────────────────────────────┐
                                │ DataSources                          │
                                │ DataSource: lookup → fetch → mapping │
                                │ Internal/: workers, process runners  │
                                └──────────────────┬───────────────────┘
                                                   ▼
                                ┌──────────────────────────────────────┐
                                │ Quotas — UsageSnapshot, UsageQuota,  │
                                │ UsageError, plans, costs (no I/O)    │
                                └──────────────────────────────────────┘
                     (+ Diagnostics: AppLog, importable by anyone)
```

Arrows point at the supplier. A module never imports `Domain`.

## Pattern: a provider needs something new

Most provider features are a line of JSON plus, at most, one generic piece:

```
┌──────────────┐    ┌───────────────────────────────┐    ┌──────────────┐
│ <id>.json    │───▶│ DataSources                   │───▶│ UsageSnapshot│
│ "where": …   │    │ JSONMapper learns `where`     │    │ (Quotas)     │
│ (new rule)   │    │ (generic, tested in           │    └──────────────┘
└──────────────┘    │  DataSourcesTests)            │
                    └───────────────────────────────┘
```

## Pattern: a refresh, end to end

```
Timer / Refresh button
  │
  ▼
QuotaMonitor.refresh(providerId:)
  │
  ▼
Provider.refresh(kind)  ── verifyBeforeBackground? single flight
  │   active data source ── fallbackOn[tag] ── fallback (if the setting allows)
  ▼
DataSource.fetchUsage()  ── cache.ttl / remembered rate limit
  │  1 lookup   CredentialLookup (env · jsonFile · keychain · firstOf, OAuth2 refresh)
  │  2 fetch    Fetch (http · jsonRpc · cli)                 ── identity checked
  │  3 mapping  Mapping (json · text · script)
  ▼
UsageSnapshot ──▶ provider.snapshot ──▶ views
        └─ on failure: DataSourceError(step, reason: UsageError) ─▶ lastError, lastFailedStep
```

## Component Interaction Tables

### Standard Table Format

```
| Component          | Purpose                     | Inputs           | Outputs          | Dependencies   |
|--------------------|-----------------------------|------------------|------------------|----------------|
| acme.json          | Acme as data                | —                | ProviderDefinition | —            |
| JSONMapper `where` | Filter `each` elements      | response, rule   | quotas           | JSONScope      |
| Provider           | Lifecycle (unchanged)       | DataSources      | snapshot state   | settings       |
```

### Extended Table (for complex features)

```
| Component          | Module      | Public?  | Creates/Modifies | Test File                          |
|--------------------|-------------|----------|------------------|------------------------------------|
| acme.json          | Providers   | resource | Creates          | AcmeDefinitionTests.swift          |
| QuotaRule.where    | DataSources | yes      | Modifies         | DataSourceTests.swift              |
| JSONMapper         | DataSources | internal | Modifies         | (through the rule's tests)         |
| ClaudeBarApp       | App         | —        | Modifies         | AcceptanceTests (if user-visible)  |
```

### Files to Create/Modify Table

```
| File Path                                              | Action | Description                     |
|--------------------------------------------------------|--------|---------------------------------|
| Modules/Providers/Resources/Providers/acme.json        | Create | The definition                  |
| Modules/Providers/Tests/AcmeDefinitionTests.swift      | Create | Golden tests, stubbed connections |
| Modules/DataSources/Sources/Mapping.swift              | Modify | The new rule                    |
| Sources/App/ClaudeBarApp.swift                         | Modify | `Self.builtIn("acme", …)`       |
```

---

## Approval Prompt Template

After presenting the architecture, ask for user approval:

```
## Architecture Review

I've designed the architecture for [Feature Name]:

[Diagram Here]

### Components Summary

| Component | Purpose |
|-----------|---------|
| [Name]    | [Desc]  |

### Files to Create/Modify

- `Modules/.../NewFile.swift` - [Description]
- `Modules/.../Tests/NewTests.swift` - [Description]

**Ready to proceed with TDD implementation?**
```

Use AskUserQuestion with:
- "Approve - proceed with implementation"
- "Modify - I have feedback on the design"
