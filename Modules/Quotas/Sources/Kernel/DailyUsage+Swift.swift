import Foundation
import QuotaKernel

extension DailyUsageStat {
    public convenience init(
        date: Date,
        totalCost: Decimal,
        totalTokens: Int,
        workingTime: TimeInterval,
        sessionCount: Int,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cachedSavings: Decimal = 0
    ) {
        self.init(
            dateSeconds: date.kernelSeconds,
            totalCostNanos: totalCost.nanos,
            totalTokens64: Int64(totalTokens),
            workingTime: workingTime,
            sessionCount64: Int64(sessionCount),
            inputTokens64: Int64(inputTokens),
            outputTokens64: Int64(outputTokens),
            cacheCreationTokens64: Int64(cacheCreationTokens),
            cacheReadTokens64: Int64(cacheReadTokens),
            cachedSavingsNanos: cachedSavings.nanos
        )
    }

    public static func == (lhs: DailyUsageStat, rhs: DailyUsageStat) -> Bool { lhs.isEqual(rhs) }

    public var date: Date { Date(kernelSeconds: dateSeconds) }
    public var totalCost: Decimal { Decimal(nanos: totalCostNanos) }
    public var totalTokens: Int { Int(totalTokens64) }
    public var sessionCount: Int { Int(sessionCount64) }
    public var inputTokens: Int { Int(inputTokens64) }
    public var outputTokens: Int { Int(outputTokens64) }
    public var cacheCreationTokens: Int { Int(cacheCreationTokens64) }
    public var cacheReadTokens: Int { Int(cacheReadTokens64) }
    public var cachedSavings: Decimal { Decimal(nanos: cachedSavingsNanos) }
    public var totalTokensWithCache: Int { Int(totalTokensWithCache64) }
    public var totalCacheTokens: Int { Int(totalCacheTokens64) }

    public static func empty(for date: Date) -> DailyUsageStat {
        DailyUsageStat.companion.empty(dateSeconds: date.kernelSeconds)
    }

    /// "$14.26"
    public var formattedCost: String { formattedUSD(totalCost, locale: "en_US") }
    /// "19.5M"
    public var formattedTokens: String { formattedCount(totalTokens) }
    /// "22h 16m", "5m 30s"
    public var formattedWorkingTime: String {
        let hours = Int(workingTime) / 3600
        let minutes = Int(workingTime) / 60 % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(Int(workingTime) % 60)s"
    }
    /// "Mar 11"
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    /// "92.4%"
    public var formattedHitRate: String { String(format: "%.1f%%", cacheHitRate * 100) }
    /// "$412.30"
    public var formattedSavings: String { formattedUSD(cachedSavings, locale: "en_US") }
    /// "37.0M"
    public var formattedCacheTokens: String { formattedCount(totalCacheTokens) }
    /// "38.0M"
    public var formattedTotalTokensWithCache: String { formattedCount(totalTokensWithCache) }
}

// The usage-history ledger (~/.claudebar/usage-history/) keeps days as JSON. A Kotlin class
// can't adopt Codable from Swift, so a day is stored through `Stored`, whose keys and
// encodings are the ones the old Swift struct's synthesized Codable wrote.
extension DailyUsageStat {
    public struct Stored: Codable, Sendable, Equatable {
        let date: Date
        let totalCost: Decimal
        let totalTokens: Int
        let workingTime: TimeInterval
        let sessionCount: Int
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let cachedSavings: Decimal

        public var stat: DailyUsageStat {
            DailyUsageStat(
                date: date, totalCost: totalCost, totalTokens: totalTokens, workingTime: workingTime,
                sessionCount: sessionCount, inputTokens: inputTokens, outputTokens: outputTokens,
                cacheCreationTokens: cacheCreationTokens, cacheReadTokens: cacheReadTokens,
                cachedSavings: cachedSavings
            )
        }
    }

    public var stored: Stored {
        Stored(
            date: date, totalCost: totalCost, totalTokens: totalTokens, workingTime: workingTime,
            sessionCount: sessionCount, inputTokens: inputTokens, outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens, cacheReadTokens: cacheReadTokens,
            cachedSavings: cachedSavings
        )
    }
}

extension DailyUsageReport {
    public static func == (lhs: DailyUsageReport, rhs: DailyUsageReport) -> Bool { lhs.isEqual(rhs) }

    /// Positive when today cost more.
    public var costDelta: Decimal { Decimal(nanos: costDeltaNanos) }
    public var tokenDelta: Int { Int(tokenDelta64) }
    public var savingsDelta: Decimal { Decimal(nanos: savingsDeltaNanos) }
    public var cacheTokenDelta: Int { Int(cacheTokenDelta64) }
    /// The change against the previous day as a percentage; nil when that day had none.
    public var costChangePercent: Double? { costChangePercentOrNull.swift }
    public var tokenChangePercent: Double? { tokenChangePercentOrNull.swift }
    public var timeChangePercent: Double? { timeChangePercentOrNull.swift }

    /// "-$27.47", "+$5.00"
    public var formattedCostDelta: String { signed(costDelta) }
    /// "+$212.30"
    public var formattedSavingsDelta: String { signed(savingsDelta) }
    /// "-40.2M", "+1.5K"
    public var formattedTokenDelta: String { (tokenDelta >= 0 ? "+" : "-") + formattedCount(abs(tokenDelta)) }
    /// "+17.0M"
    public var formattedCacheTokenDelta: String {
        (cacheTokenDelta >= 0 ? "+" : "-") + formattedCount(abs(cacheTokenDelta))
    }
    /// "+2h 39m", "-45m"
    public var formattedTimeDelta: String {
        let delta = abs(timeDelta)
        let sign = timeDelta >= 0 ? "+" : "-"
        let hours = Int(delta) / 3600
        let minutes = Int(delta) / 60 % 60
        return hours > 0 ? "\(sign)\(hours)h \(minutes)m" : "\(sign)\(minutes)m"
    }
    /// "+7.0pp", "-3.5pp"
    public var formattedCacheHitRateDelta: String {
        let points = cacheHitRateDelta * 100
        return String(format: "\(points >= 0 ? "+" : "-")%.1fpp", abs(points))
    }

    private func signed(_ amount: Decimal) -> String {
        (amount >= 0 ? "+" : "-") + formattedUSD(abs(amount), locale: "en_US")
    }
}
