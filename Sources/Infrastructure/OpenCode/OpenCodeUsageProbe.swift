import Foundation
import Domain

/// Queries local opencode DB for Go usage quotas — 5h/$12, weekly/$30, monthly/$60.
///
/// Window semantics match the OpenCode dashboard:
/// - 5-hour: rolling window ending at `now`; reset = oldest message in window + 5h
/// - Weekly: fixed UTC Monday → Monday
/// - Monthly: anchored to the user's first opencode-go message (day-of-month preserved)
public struct OpenCodeUsageProbe: UsageProbe {

    static let fiveHourLimit: Double = 12.0
    static let weeklyLimit: Double = 30.0
    static let monthlyLimit: Double = 60.0

    private let cliExecutor: any CLIExecutor
    private let timeout: TimeInterval

    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        timeout: TimeInterval = 15.0
    ) {
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        cliExecutor.locate("opencode") != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard let opencodePath = cliExecutor.locate("opencode") else {
            throw ProbeError.cliNotFound("opencode")
        }

        let now = Date()
        let fiveHourMs = Self.millisSinceEpoch(now.addingTimeInterval(-5 * 3600))
        let weekStart = Self.startOfWeekUTC(from: now)
        let weekEnd = Self.endOfWeekUTC(from: now)

        let primary = try Self.parsePrimaryWindow(
            try runDBQuery(
                opencodePath: opencodePath,
                sql: Self.primarySQL(
                    fiveHourMs: fiveHourMs,
                    weekStartMs: Self.millisSinceEpoch(weekStart)
                )
            )
        )

        // Monthly window is anchored to the user's first opencode-go message; skip query if none.
        let monthlyCost: Double
        let monthEnd: Date
        if let anchorMs = primary.anchorMs {
            let anchor = Date(timeIntervalSince1970: TimeInterval(anchorMs) / 1000)
            let bounds = Self.anchoredMonthBounds(now: now, anchor: anchor)
            monthEnd = bounds.end
            monthlyCost = try Self.parseMonthlyCost(
                try runDBQuery(
                    opencodePath: opencodePath,
                    sql: Self.monthlySQL(
                        monthStartMs: Self.millisSinceEpoch(bounds.start),
                        monthEndMs: Self.millisSinceEpoch(bounds.end)
                    )
                )
            )
        } else {
            monthlyCost = 0
            monthEnd = now.addingTimeInterval(30 * 86400)
        }

        let fiveHourRemaining = Self.percentRemaining(used: primary.fiveHourCost, limit: Self.fiveHourLimit)
        let weeklyRemaining = Self.percentRemaining(used: primary.weeklyCost, limit: Self.weeklyLimit)
        let monthlyRemaining = Self.percentRemaining(used: monthlyCost, limit: Self.monthlyLimit)

        let quotas: [UsageQuota] = [
            UsageQuota(
                percentRemaining: fiveHourRemaining,
                quotaType: .session,
                providerId: "opencode-go",
                resetsAt: Self.fiveHourResetDate(from: primary.fiveHourOldestMs, fallback: now)
            ),
            UsageQuota(
                percentRemaining: weeklyRemaining,
                quotaType: .weekly,
                providerId: "opencode-go",
                resetsAt: weekEnd
            ),
            UsageQuota(
                percentRemaining: monthlyRemaining,
                quotaType: .timeLimit("Monthly"),
                providerId: "opencode-go",
                resetsAt: monthEnd
            ),
        ]

        AppLog.probes.info("OpenCode probe success: 5hr \(Int(fiveHourRemaining))%, weekly \(Int(weeklyRemaining))%, monthly \(Int(monthlyRemaining))%")

        return UsageSnapshot(
            providerId: "opencode-go",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - DB Queries

    /// Filtered row source: opencode-go assistant messages with a numeric cost,
    /// using `data.time.created` when present (fallback to the column).
    private static let filteredSubquery = """
    SELECT
      CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS t,
      CAST(json_extract(data, '$.cost') AS REAL) AS cost
    FROM message
    WHERE json_valid(data)
      AND json_extract(data, '$.providerID') = 'opencode-go'
      AND json_extract(data, '$.role') = 'assistant'
      AND json_type(data, '$.cost') IN ('integer', 'real')
    """

    static func primarySQL(fiveHourMs: Int64, weekStartMs: Int64) -> String {
        """
        SELECT
          COALESCE(SUM(CASE WHEN t >= \(fiveHourMs) THEN cost ELSE 0 END), 0) AS five_hour_cost,
          COALESCE(SUM(CASE WHEN t >= \(weekStartMs) THEN cost ELSE 0 END), 0) AS weekly_cost,
          MIN(CASE WHEN t >= \(fiveHourMs) THEN t ELSE NULL END) AS five_hour_oldest_ms,
          MIN(t) AS anchor_ms
        FROM (\(filteredSubquery))
        """
    }

    static func monthlySQL(monthStartMs: Int64, monthEndMs: Int64) -> String {
        """
        SELECT COALESCE(SUM(cost), 0) AS monthly_cost
        FROM (\(filteredSubquery))
        WHERE t >= \(monthStartMs) AND t < \(monthEndMs)
        """
    }

    private func runDBQuery(opencodePath: String, sql: String) throws -> Data {
        let result = try cliExecutor.execute(
            binary: opencodePath,
            args: ["db", sql, "--format", "json"],
            input: nil,
            timeout: timeout,
            workingDirectory: nil,
            autoResponses: [:]
        )

        guard result.exitCode == 0 else {
            AppLog.probes.error("OpenCode: DB query failed with exit code \(result.exitCode)")
            throw ProbeError.executionFailed("opencode db exited with code \(result.exitCode)")
        }

        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = output.data(using: .utf8) else {
            throw ProbeError.parseFailed("Failed to encode query output")
        }

        return data
    }

    // MARK: - Parsing (testable)

    static func parsePrimaryWindow(_ data: Data) throws -> PrimaryWindow {
        struct Row: Decodable {
            let five_hour_cost: Double
            let weekly_cost: Double
            let five_hour_oldest_ms: Int64?
            let anchor_ms: Int64?
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard let row = rows.first else {
            throw ProbeError.parseFailed("No primary window data")
        }
        return PrimaryWindow(
            fiveHourCost: row.five_hour_cost,
            weeklyCost: row.weekly_cost,
            fiveHourOldestMs: row.five_hour_oldest_ms,
            anchorMs: row.anchor_ms
        )
    }

    static func parseMonthlyCost(_ data: Data) throws -> Double {
        struct Row: Decodable { let monthly_cost: Double }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.first?.monthly_cost ?? 0
    }

    /// Returns percentage remaining, clamped to [0, 100]. Over-limit → 0% → .depleted.
    static func percentRemaining(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 100 }
        return max(0, min(100, (limit - used) / limit * 100))
    }

    // MARK: - Time helpers (UTC)

    static func millisSinceEpoch(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    static func fiveHourResetDate(from oldestMs: Int64?, fallback now: Date) -> Date {
        guard let oldestMs else {
            return now.addingTimeInterval(5 * 3600)
        }
        return Date(timeIntervalSince1970: TimeInterval(oldestMs) / 1000)
            .addingTimeInterval(5 * 3600)
    }

    /// UTC Monday at 00:00:00 of the week containing `date`.
    static func startOfWeekUTC(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let weekday = cal.component(.weekday, from: date)   // 1=Sun, 2=Mon, ..., 7=Sat
        let daysFromMonday = (weekday + 5) % 7              // Mon=0, Tue=1, ..., Sun=6
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
        return cal.startOfDay(for: monday)
    }

    /// UTC Monday at 00:00:00 of the week AFTER the week containing `date`.
    static func endOfWeekUTC(from date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal.date(byAdding: .day, value: 7, to: startOfWeekUTC(from: date)) ?? date
    }

    /// Returns the current monthly window `[start, end)` anchored to the day-of-month and
    /// time-of-day of `anchor`. E.g., anchor = Mar 14 14:30 UTC, now = Apr 2 →
    /// `[Mar 14 14:30, Apr 14 14:30)`. When the anchor day doesn't exist in the target month
    /// (e.g., 31), Calendar clamps to the last valid day.
    static func anchoredMonthBounds(now: Date, anchor: Date) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let anchorTime = cal.dateComponents([.day, .hour, .minute, .second], from: anchor)
        let nowMonth = cal.dateComponents([.year, .month], from: now)

        var comps = DateComponents()
        comps.year = nowMonth.year
        comps.month = nowMonth.month
        comps.day = anchorTime.day
        comps.hour = anchorTime.hour
        comps.minute = anchorTime.minute
        comps.second = anchorTime.second

        var start = cal.date(from: comps) ?? anchor
        if start > now {
            start = cal.date(byAdding: .month, value: -1, to: start) ?? start
        }
        let end = cal.date(byAdding: .month, value: 1, to: start)
            ?? start.addingTimeInterval(30 * 86400)
        return (start, end)
    }
}

struct PrimaryWindow: Sendable, Equatable {
    let fiveHourCost: Double
    let weeklyCost: Double
    let fiveHourOldestMs: Int64?
    let anchorMs: Int64?
}
