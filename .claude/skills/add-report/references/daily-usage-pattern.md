# Daily Usage Pattern — Reference Implementation

*TODAY'S USAGE* — Claude's daily cost, tokens and working time against the
day before — as the reference for new report cards. Since UH2 it is data:
Claude's logs, prices and local-route rule live in `claude.json` and
`claude-prices.json`; the engine names no vendor
([TARGET_ARCHITECTURE §10](../../../../docs/architecture/TARGET_ARCHITECTURE.md#10--usage-history-as-data)).

## File Map

```
Modules/Providers/Resources/Providers/
├── claude.json                   # "usageHistory": files · where · at · id · model · tokens · prices · freeWhen · sessionGap
└── claude-prices.json            # per-model prices, families, free families, fallback — a price change edits this

Modules/DataSources/Sources/
├── UsageLog.swift                # UsageLog (days(in:)) + UsageLog.Definition (the JSON)
└── Internal/Logs/
    ├── LogRecord.swift           # the one record every reader yields; RecordShape reads it with the path language
    ├── JSONLinesReader.swift     # jsonLines: incremental, appended lines only, byte prefilter from `where`
    ├── LogFileFinder.swift       # the `files` glob, changed since the range's first day
    ├── PriceList.swift           # exact → longest prefix → family → free → local route → otherwise
    ├── LocalEndpoint.swift       # freeWhen.localEndpoint (#190)
    └── DayAggregator.swift       # dedupe (last wins, #207), local days, sessions by sessionGap

Modules/Providers/Sources/
├── UsageHistory.swift            # one per login: report (today vs yesterday), read(), days(in:)
└── Account.swift                 # account.usageHistory — the default login's, nil when not offered

Modules/Quotas/Sources/
├── DailyUsageStat.swift          # one day, with formatting (becomes Day)
├── DailyUsageReport.swift        # today vs yesterday with deltas
└── DateRange.swift               # a run of local days

Sources/App/Views/
├── DailyUsageCardView.swift      # card + DailyUsageMetric
└── MenuContentView.swift         # reads (provider as? Account)?.usageHistory?.report

Tests:
├── Modules/DataSources/Tests/Logs/   # neutral fixtures: reader, prices, local route, the whole log
└── Modules/Providers/Tests/ClaudeUsageHistoryTests.swift   # the old analyzer's cases through claude.json
```

## Data Flow

```
claude.json "usageHistory"  ──▶ DataSources.makeUsageLog ──▶ UsageLog (one per login)
~/.claude/projects/**/*.jsonl ─▶ JSONLinesReader ─▶ [LogRecord] ─▶ deduplicated
                                                   ─▶ DayAggregator (+ PriceList, LocalEndpoint for today)
                                                   ─▶ [DailyUsageStat], one per day of the range
UsageHistory.read() ─▶ report (last 2 days) ─▶ MenuContentView ─▶ DailyUsageCardView × 3
```

## Key Design Decisions

1. **The login owns it** — `account.usageHistory`, never a dictionary keyed by
   provider ids; `nil` when the definition declares no `usageHistory`.
2. **What differs per tool is data** — paths, options, a script as the escape
   hatch, a new `format` only for a new kind of file.
3. **Read on popover open, never in the background** (#204).
4. **Performance** — only files changed since the range's first day; appended
   lines only; lines without the `where` text are never decoded.
5. **Formatting in domain models** — views read `formattedCost`, `formattedTokens`.
6. **Cards match existing style** — `theme.cardGradient`, `theme.glassBorder`;
   Cost and Tokens side by side, Working Time full width below.
