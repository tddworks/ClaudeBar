import Foundation

/// A single day's aggregated usage statistics from Claude Code session logs.
/// Rich domain model with formatting behavior.
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md) — leaves the kernel for `UsageHistory` (§7) with `DailyUsageReport`.
public struct DailyUsageStat: Sendable, Equatable, Codable {
    /// The date this stat represents (day granularity)
    public let date: Date

    /// Total estimated cost in USD (includes input, output, and cache token costs)
    public let totalCost: Decimal

    /// Total non-cache tokens consumed (input + output only)
    public let totalTokens: Int

    /// Total working time in seconds (wall clock across sessions)
    public let workingTime: TimeInterval

    /// Number of sessions in this day
    public let sessionCount: Int

    /// Raw input tokens (excludes cache)
    public let inputTokens: Int

    /// Raw output tokens
    public let outputTokens: Int

    /// Tokens written to cache (cache_creation_input_tokens)
    public let cacheCreationTokens: Int

    /// Tokens served from cache (cache_read_input_tokens)
    public let cacheReadTokens: Int

    /// Estimated USD saved by cache hits vs full input price
    public let cachedSavings: Decimal

    /// One line per model, ordered by name — the lines a chart stacks. Empty
    /// when the day came from a log that doesn't name models.
    public let lines: [ModelUsageLine]

    public init(
        date: Date,
        totalCost: Decimal,
        totalTokens: Int,
        workingTime: TimeInterval,
        sessionCount: Int,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cachedSavings: Decimal = 0,
        lines: [ModelUsageLine] = []
    ) {
        self.date = date
        self.totalCost = totalCost
        self.totalTokens = totalTokens
        self.workingTime = workingTime
        self.sessionCount = sessionCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.cachedSavings = cachedSavings
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey {
        case date, totalCost, totalTokens, workingTime, sessionCount
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens, cachedSavings, lines
    }

    /// Days kept before lines existed decode without them.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        totalCost = try container.decode(Decimal.self, forKey: .totalCost)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        workingTime = try container.decode(TimeInterval.self, forKey: .workingTime)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        cachedSavings = try container.decodeIfPresent(Decimal.self, forKey: .cachedSavings) ?? 0
        lines = try container.decodeIfPresent([ModelUsageLine].self, forKey: .lines) ?? []
    }

    // MARK: - Formatting

    /// Formatted cost string (e.g., "$14.26")
    public var formattedCost: String {
        MoneyFormat.string(totalCost)
    }

    /// Formatted token count (e.g., "19.5M", "1.2K", "500")
    public var formattedTokens: String {
        if totalTokens >= 1_000_000 {
            let millions = Double(totalTokens) / 1_000_000.0
            return String(format: "%.1fM", millions)
        } else if totalTokens >= 1_000 {
            let thousands = Double(totalTokens) / 1_000.0
            return String(format: "%.1fK", thousands)
        }
        return "\(totalTokens)"
    }

    /// Formatted working time (e.g., "22h 16m", "5m 30s")
    public var formattedWorkingTime: String {
        let hours = Int(workingTime) / 3600
        let minutes = Int(workingTime) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            let seconds = Int(workingTime) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    /// Formatted date (e.g., "Mar 11")
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Whether this day has any usage
    public var isEmpty: Bool {
        totalTokens == 0 && totalCost == 0 && workingTime == 0
    }

    /// An empty stat for a given date
    public static func empty(for date: Date) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: 0, totalTokens: 0, workingTime: 0, sessionCount: 0)
    }

    // MARK: - Cache

    /// All tokens including cache: `totalTokens` (input + output, or the
    /// log's own total when it keeps only that) + cache_creation + cache_read.
    public var totalTokensWithCache: Int {
        totalTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Total cache tokens (creation + read)
    public var totalCacheTokens: Int {
        cacheCreationTokens + cacheReadTokens
    }

    /// Cache hit rate: portion of input that was served from cache.
    /// Formula: cache_read / (cache_read + input). Returns 0 when denominator is zero.
    public var cacheHitRate: Double {
        let denom = cacheReadTokens + inputTokens
        guard denom > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(denom)
    }

    /// Formatted cache hit rate (e.g., "92.4%")
    public var formattedHitRate: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }

    /// Formatted cached savings (e.g., "$412.30")
    public var formattedSavings: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: cachedSavings as NSDecimalNumber) ?? "$\(cachedSavings)"
    }

    /// Formatted cache token count (e.g., "37.0M")
    public var formattedCacheTokens: String {
        let total = totalCacheTokens
        if total >= 1_000_000 {
            return String(format: "%.1fM", Double(total) / 1_000_000.0)
        } else if total >= 1_000 {
            return String(format: "%.1fK", Double(total) / 1_000.0)
        }
        return "\(total)"
    }

    /// Formatted total tokens including cache (e.g., "38.0M")
    public var formattedTotalTokensWithCache: String {
        let total = totalTokensWithCache
        if total >= 1_000_000 {
            return String(format: "%.1fM", Double(total) / 1_000_000.0)
        } else if total >= 1_000 {
            return String(format: "%.1fK", Double(total) / 1_000.0)
        }
        return "\(total)"
    }
}
