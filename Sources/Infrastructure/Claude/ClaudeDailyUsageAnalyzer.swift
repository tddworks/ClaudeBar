import Foundation
import Domain

/// Analyzes Claude Code session JSONL files to produce daily usage reports.
/// Reads from ~/.claude/projects/*/*.jsonl
public struct ClaudeDailyUsageAnalyzer: DailyUsageAnalyzing, Sendable {
    private let claudeDir: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    /// Whether Claude Code is pointed at a loopback endpoint, i.e. inference
    /// nobody bills per token (#190). Resolved per scan, not at init, so routing
    /// the CLI at a local server takes effect on the next scan. Applies to today's
    /// records only — it describes the current route, and the window reaches back a day.
    private let isLocallyServed: @Sendable () -> Bool

    /// - Parameter isLocallyServed: defaults to `false` so tests never read the
    ///   real `~/.claude.json`; the app injects `ClaudeLocalInferenceDetector`.
    public init(
        claudeDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude"),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        isLocallyServed: @escaping @Sendable () -> Bool = { false }
    ) {
        self.claudeDir = claudeDir
        self.calendar = calendar
        self.now = now
        self.isLocallyServed = isLocallyServed
    }

    public func analyzeToday() async throws -> DailyUsageReport {
        let currentDate = now()
        let todayStart = calendar.startOfDay(for: currentDate)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let servedLocally = isLocallyServed()
        if servedLocally {
            AppLog.probes.debug("DailyUsage: routed at a local endpoint — unpriced models cost nothing")
        }

        // Only scan files modified in the last 2 days for performance
        let projectsDir = claudeDir.appendingPathComponent("projects")
        let jsonlFiles = findRecentJSONLFiles(in: projectsDir, since: yesterdayStart)

        AppLog.probes.info("DailyUsage: scanning \(jsonlFiles.count) recent JSONL files")

        // Parse files and collect records
        let parser = SessionJSONLParser()
        var parsedRecords: [TokenUsageRecord] = []
        for fileURL in jsonlFiles {
            if let records = try? parser.parse(fileURL: fileURL) {
                parsedRecords.append(contentsOf: records)
            }
        }

        // Claude Code repeats the same `message.usage` across streamed content blocks,
        // parallel tool calls, and resumed/branched session files. Collapse duplicates by
        // (message.id, requestId) — keeping the last/most-complete entry — before summing,
        // so cost/token totals match `claude /cost` instead of inflating several-fold.
        // See docs/features/daily-usage/design.md and issue #207.
        let allRecords = deduplicateLastWins(parsedRecords)

        AppLog.probes.info("DailyUsage: \(parsedRecords.count) raw records, \(allRecords.count) after dedup")

        // Partition into today and yesterday
        let todayRecords = allRecords.filter { record in
            record.timestamp >= todayStart && record.timestamp < todayStart.addingTimeInterval(86400)
        }
        let yesterdayRecords = allRecords.filter { record in
            record.timestamp >= yesterdayStart && record.timestamp < todayStart
        }

        // Aggregate stats.
        //
        // `servedLocally` is a *current* setting, so it prices today only. Applying it
        // to the whole two-day window would retroactively zero yesterday's estimate for
        // unpriced names — the same erasure rule 1 exists to prevent, just one day
        // earlier. Yesterday therefore keeps its Sonnet-rate estimate, which over-reports
        // local spend if the CLI was routed locally all day; over-reporting is the safe
        // direction, since the alternative is a cost that silently disappears.
        let todayStat = aggregate(records: todayRecords, date: todayStart, servedLocally: servedLocally)
        let yesterdayStat = aggregate(records: yesterdayRecords, date: yesterdayStart, servedLocally: false)

        AppLog.probes.info("DailyUsage: today=\(todayStat.formattedCost)/\(todayStat.formattedTokens), yesterday=\(yesterdayStat.formattedCost)/\(yesterdayStat.formattedTokens)")

        return DailyUsageReport(today: todayStat, previous: yesterdayStat)
    }

    // MARK: - Private

    /// Dedup key for a usage record. A record carrying both `messageId` and `requestId`
    /// groups by that composite; records missing either are kept distinct (unique sentinel)
    /// so they are never merged with unrelated records.
    private enum DedupKey: Hashable {
        case composite(String, String)
        case unkeyed(Int)
    }

    /// Collapse records sharing a `(messageId, requestId)` to a single entry, keeping the
    /// **last** occurrence in input order. Streaming snapshots accumulate `output_tokens`,
    /// so the final line holds the complete, billed value (last-wins == max-wins). Output
    /// order preserves first-seen position for stable downstream aggregation.
    private func deduplicateLastWins(_ records: [TokenUsageRecord]) -> [TokenUsageRecord] {
        var lastByKey: [DedupKey: TokenUsageRecord] = [:]
        var order: [DedupKey] = []
        var sentinel = 0

        for record in records {
            let key: DedupKey
            if let id = record.messageId, let req = record.requestId {
                key = .composite(id, req)
            } else {
                key = .unkeyed(sentinel)
                sentinel += 1
            }
            if lastByKey[key] == nil { order.append(key) }
            lastByKey[key] = record
        }

        return order.compactMap { lastByKey[$0] }
    }

    /// Only find JSONL files modified since the given date (performance optimization).
    private func findRecentJSONLFiles(in directory: URL, since: Date) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            // Only include files modified since yesterday
            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate >= since {
                files.append(fileURL)
            }
        }
        return files
    }

    private func aggregate(records: [TokenUsageRecord], date: Date, servedLocally: Bool) -> DailyUsageStat {
        guard !records.isEmpty else { return .empty(for: date) }

        var totalCost: Decimal = 0
        var totalTokens = 0
        var inputTokens = 0
        var outputTokens = 0
        var cacheCreationTokens = 0
        var cacheReadTokens = 0
        var cachedSavings: Decimal = 0

        for record in records {
            totalCost += ModelPricing.cost(for: record, servedLocally: servedLocally)
            totalTokens += record.totalTokens
            inputTokens += record.inputTokens
            outputTokens += record.outputTokens
            cacheCreationTokens += record.cacheCreationTokens
            cacheReadTokens += record.cacheReadTokens
            cachedSavings += ModelPricing.savings(for: record, servedLocally: servedLocally)
        }

        // Estimate working time from session timestamps (first to last message per session)
        // Group records by approximate sessions (gaps > 30 min = new session)
        let sortedRecords = records.sorted { $0.timestamp < $1.timestamp }
        var workingTime: TimeInterval = 0
        var sessionCount = 1
        var sessionStart = sortedRecords[0].timestamp
        var lastTimestamp = sortedRecords[0].timestamp

        for record in sortedRecords.dropFirst() {
            let gap = record.timestamp.timeIntervalSince(lastTimestamp)
            if gap > 1800 { // 30 minute gap = new session
                workingTime += lastTimestamp.timeIntervalSince(sessionStart)
                sessionStart = record.timestamp
                sessionCount += 1
            }
            lastTimestamp = record.timestamp
        }
        workingTime += lastTimestamp.timeIntervalSince(sessionStart)

        return DailyUsageStat(
            date: date,
            totalCost: totalCost,
            totalTokens: totalTokens,
            workingTime: workingTime,
            sessionCount: sessionCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens,
            cachedSavings: cachedSavings
        )
    }
}
