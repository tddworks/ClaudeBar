import Foundation

/// A single day's aggregated usage statistics from Claude Code session logs.
/// Rich domain model with formatting behavior.
public struct DailyUsageStat: Sendable, Equatable {
    /// The date this stat represents (day granularity)
    public let date: Date

    /// Total estimated cost in USD
    public let totalCost: Decimal

    /// Total tokens consumed (input + output + cache)
    public let totalTokens: Int

    /// Total working time in seconds (wall clock across sessions)
    public let workingTime: TimeInterval

    /// Number of sessions in this day
    public let sessionCount: Int

    public init(
        date: Date,
        totalCost: Decimal,
        totalTokens: Int,
        workingTime: TimeInterval,
        sessionCount: Int
    ) {
        self.date = date
        self.totalCost = totalCost
        self.totalTokens = totalTokens
        self.workingTime = workingTime
        self.sessionCount = sessionCount
    }

    // MARK: - Formatting

    /// Formatted cost string (e.g., "$14.26")
    public var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalCost as NSDecimalNumber) ?? "$\(totalCost)"
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
}
