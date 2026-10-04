# Report Card Architecture

This document describes ClaudeBar's report card system — analytics cards that parse local data sources, aggregate metrics, and display comparisons within the existing provider UI.

## Overview

Report cards extend the provider view with **aggregated analytics** derived from local data. Unlike quota cards (which show real-time API/CLI probe results), report cards analyze historical session data to show trends and comparisons.

```
┌──────────────────────────────────────────────────────┐
│  Provider View (e.g., Claude)                         │
│  ┌────────────┐  ┌────────────┐                      │
│  │ SESSION 85%│  │ WEEKLY 62% │  ← Quota cards       │
│  └────────────┘  └────────────┘                      │
│  ┌────────────┐                                       │
│  │ SONNET 60% │                                       │
│  └────────────┘                                       │
│  ┌────────────┐  ┌────────────┐                      │
│  │COST $371.72│  │TOKEN 184.8M│  ← Report cards      │
│  └────────────┘  └────────────┘                      │
│  ┌─────────────────────────────┐                      │
│  │ WORKING TIME  4h 11m       │                       │
│  └─────────────────────────────┘                      │
└──────────────────────────────────────────────────────┘
```

## Design Principles

### 1. Reports are Per-Provider

Each report belongs to a specific provider and lives on `UsageSnapshot`, not `QuotaMonitor`. This follows the existing pattern where `costUsage` and `bedrockUsage` are snapshot-level data.

```swift
// UsageSnapshot owns all per-provider data
public struct UsageSnapshot {
    public let quotas: [UsageQuota]           // Quota cards
    public let costUsage: CostUsage?          // API cost card
    public let dailyUsageReport: DailyUsageReport? // Daily usage cards
    // Future: weeklyReport, modelBreakdownReport, etc.
}
```

### 2. Analyzer Injected into Provider

The provider's definition declares how its logs read (`usageHistory`); each login owns the result, read when the popover opens — never attached to the snapshot.

```
Account (a login)
├── usage                 ← its data sources → quotas
└── usageHistory          ← UsageLog, built from the definition's usageHistory → days
```

### 3. Infrastructure is Provider-Scoped

Since each data source is provider-specific (e.g., `~/.claude/projects/` is Claude-only), the parser and analyzer live in the provider's infrastructure folder.

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        DOMAIN LAYER                               │
│                                                                    │
│  Sources/Domain/{Feature}/                                        │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │ {Name}Stat       │  │ {Name}Report     │  │ {Name}Analyzing│  │
│  │ (rich model,     │  │ (current vs prev,│  │ (@Mockable     │  │
│  │  formatting)     │  │  deltas, %)      │  │  protocol)     │  │
│  └──────────────────┘  └──────────────────┘  └────────────────┘  │
│                                                                    │
│  Sources/Domain/Provider/UsageSnapshot.swift                      │
│  └── {name}Report: {Name}Report?  (optional field)               │
│                                                                    │
│  Sources/Domain/Provider/{Provider}/{Provider}Provider.swift      │
│  └── attach{Name}Report(to: snapshot) → enriched snapshot        │
├──────────────────────────────────────────────────────────────────┤
│                     INFRASTRUCTURE LAYER                           │
│                                                                    │
│  Sources/Infrastructure/{Provider}/                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │ {Name}Parser     │  │ {Provider}{Name} │  │ Pricing/Config │  │
│  │ (file → records) │  │ Analyzer         │  │ (lookup tables)│  │
│  │                  │  │ (implements      │  │                │  │
│  │                  │  │  protocol)       │  │                │  │
│  └──────────────────┘  └──────────────────┘  └────────────────┘  │
├──────────────────────────────────────────────────────────────────┤
│                          APP LAYER                                 │
│                                                                    │
│  Sources/App/Views/                                               │
│  ┌──────────────────┐  ┌──────────────────────────────────────┐  │
│  │ {Name}CardView   │  │ MenuContentView.statsGrid()          │  │
│  │ (glassmorphism   │  │ └── if let report = snapshot.{name}  │  │
│  │  card + delta)   │  │         {Name}CardView(...)           │  │
│  └──────────────────┘  └──────────────────────────────────────┘  │
│                                                                    │
│  Sources/App/ClaudeBarApp.swift                                   │
│  └── {Provider}Provider(..., {name}Analyzer: Analyzer())         │
└──────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
Local Data Source (e.g., ~/.claude/projects/*/*.jsonl)
    │
    │ File system enumeration (filtered by modification date)
    ▼
Reader (e.g., JSONLinesReader, configured by a definition's usageHistory)
    │
    │ Extracts structured records (tokens, timestamps, models)
    ▼
Aggregator (e.g., DayAggregator, priced by a PriceList)
    │
    │ Partitions by time period, aggregates metrics
    ▼
Report Model (e.g., DailyUsageReport)
    │
    │ Attached to UsageSnapshot in Provider.refresh()
    ▼
UsageSnapshot.{name}Report
    │
    │ SwiftUI @Observable change propagation
    ▼
statsGrid() → CardView(s)
```

## Current Implementation: Daily Usage Report

The first report card implementation analyzes Claude Code session JSONL files to show daily cost, token usage, and working time with comparison to the previous day.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `DailyUsageStat` | `Domain/DailyUsage/` | One day's metrics with formatting |
| `DailyUsageReport` | `Domain/DailyUsage/` | Today vs yesterday with deltas |
| `usageHistory` + `claude-prices.json` | `Modules/Providers/Resources/Providers/` | Where Claude's logs are, how a record reads, what a token costs |
| `UsageLog`, `JSONLinesReader`, `PriceList`, `DayAggregator` | `Modules/DataSources` | Reads, prices and sums any tool's logs into days |
| `UsageHistory` | `Modules/Providers` | One per login, `account.usageHistory` |
| `DailyUsageCardView` | `App/Views/` | Three metric cards |

### Data Source

Claude Code stores session data as JSONL files:
```
~/.claude/projects/{encoded-project-path}/{sessionId}.jsonl
```

Each assistant message contains token usage:
```json
{
  "type": "assistant",
  "message": {
    "model": "claude-sonnet-4-6",
    "usage": {
      "input_tokens": 100,
      "output_tokens": 50,
      "cache_creation_input_tokens": 200,
      "cache_read_input_tokens": 30
    }
  },
  "timestamp": "2026-03-11T10:00:00.000Z"
}
```

### Metrics

| Card | Metric | Source | Color |
|------|--------|--------|-------|
| Cost Usage | USD spent | tokens × model pricing | Yellow |
| Token Usage | Total tokens | sum of all token fields | Green |
| Working Time | Duration | first-to-last message gap (30min session boundary) | Purple |

### Comparison

Each metric shows a delta vs the previous day:
```
Vs Mar 10 +$17.25 (4.9%)
```

- Green delta = reduced (good for cost/tokens)
- Orange delta = increased
- Neutral for working time

### Performance

With 2000+ JSONL files on disk, the analyzer only scans files modified in the last 2 days using `contentModificationDateKey` from file resource values.

## Card UI Pattern

All report cards follow the same glassmorphism style as quota cards:

```
┌─────────────────────────────────┐
│ $ COST USAGE                    │  ← Icon + label (uppercased)
│                                  │
│ $371.72              Spent      │  ← Large value + unit
│ ████████████░░░░░░░░░░░░░░░░░  │  ← Animated progress bar
│ ⇄ Vs Mar 10 +$17.25 (4.9%)    │  ← Delta comparison
└─────────────────────────────────┘
```

**Styling tokens:**
- `theme.cardGradient` — card background
- `theme.glassBorder` — 1pt stroke
- `theme.cardCornerRadius` — corners
- `theme.progressTrack` — bar background
- `theme.textPrimary` / `textSecondary` / `textTertiary` — text hierarchy
- `theme.fontDesign` — font family
- `.padding(12)` — card padding
- Hover scale effect (1.015×)
- Cascading animation delay per card

## Future Report Ideas

| Report | Data Source | Provider | Metrics |
|--------|-----------|----------|---------|
| Weekly Summary | JSONL sessions | Claude | Week-over-week cost, tokens, sessions |
| Model Breakdown | JSONL sessions | Claude | Per-model cost distribution |
| Session Analytics | JSONL sessions | Claude | Avg session length, task count |
| API Cost Trend | API responses | Any API provider | Daily/weekly API spend |

## Testing Strategy

Following Chicago School TDD (state verification):

**Domain tests** — Verify formatting, deltas, edge cases (nil when previous is zero, empty stats):
```
Tests/DomainTests/{Feature}/{Name}StatTests.swift
Tests/DomainTests/{Feature}/{Name}ReportTests.swift
```

**Infrastructure tests** — Verify parsing, date partitioning, cost calculation:
```
Tests/InfrastructureTests/{Provider}/{Name}ParserTests.swift
Tests/InfrastructureTests/{Provider}/{Name}AnalyzerTests.swift
```

Analyzer tests use temp directories with test JSONL content — no real `~/.claude` dependency.

## Related Documents

- [Architecture Overview](ARCHITECTURE.md) — Layered architecture and QuotaMonitor
- [Theme Design](THEME_DESIGN.md) — Card styling tokens and theme system
- [add-report skill](../../.claude/skills/add-report/SKILL.md) — Step-by-step guide for adding new reports
