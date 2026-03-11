import Foundation

/// Compares today's usage against a previous day.
/// Rich domain model providing delta calculations and formatted comparisons.
public struct DailyUsageReport: Sendable, Equatable {
    /// Today's usage stats
    public let today: DailyUsageStat

    /// Previous day's usage stats (for comparison)
    public let previous: DailyUsageStat

    public init(today: DailyUsageStat, previous: DailyUsageStat) {
        self.today = today
        self.previous = previous
    }

    // MARK: - Cost Delta

    /// Cost difference (positive = more than previous, negative = less)
    public var costDelta: Decimal {
        today.totalCost - previous.totalCost
    }

    /// Cost change percentage relative to previous day (nil if previous was zero)
    public var costChangePercent: Double? {
        guard previous.totalCost > 0 else { return nil }
        let change = (today.totalCost - previous.totalCost) / previous.totalCost * 100
        return Double(truncating: change as NSDecimalNumber)
    }

    /// Formatted cost delta (e.g., "-$27.47", "+$5.00")
    public var formattedCostDelta: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let absCost = abs(costDelta)
        let formatted = formatter.string(from: absCost as NSDecimalNumber) ?? "$\(absCost)"
        let sign = costDelta >= 0 ? "+" : "-"
        return "\(sign)\(formatted)"
    }

    // MARK: - Token Delta

    /// Token difference
    public var tokenDelta: Int {
        today.totalTokens - previous.totalTokens
    }

    /// Token change percentage relative to previous day
    public var tokenChangePercent: Double? {
        guard previous.totalTokens > 0 else { return nil }
        return Double(tokenDelta) / Double(previous.totalTokens) * 100
    }

    /// Formatted token delta (e.g., "-40.2M", "+1.5K")
    public var formattedTokenDelta: String {
        let absDelta = abs(tokenDelta)
        let sign = tokenDelta >= 0 ? "+" : "-"

        let formatted: String
        if absDelta >= 1_000_000 {
            formatted = String(format: "%.1fM", Double(absDelta) / 1_000_000.0)
        } else if absDelta >= 1_000 {
            formatted = String(format: "%.1fK", Double(absDelta) / 1_000.0)
        } else {
            formatted = "\(absDelta)"
        }
        return "\(sign)\(formatted)"
    }

    // MARK: - Working Time Delta

    /// Working time difference in seconds
    public var timeDelta: TimeInterval {
        today.workingTime - previous.workingTime
    }

    /// Working time change percentage
    public var timeChangePercent: Double? {
        guard previous.workingTime > 0 else { return nil }
        return timeDelta / previous.workingTime * 100
    }

    /// Formatted time delta (e.g., "+2h 39m", "-45m")
    public var formattedTimeDelta: String {
        let absDelta = abs(timeDelta)
        let sign = timeDelta >= 0 ? "+" : "-"
        let hours = Int(absDelta) / 3600
        let minutes = Int(absDelta) / 60 % 60

        if hours > 0 {
            return "\(sign)\(hours)h \(minutes)m"
        } else {
            return "\(sign)\(minutes)m"
        }
    }

    // MARK: - Progress (for bar display)

    /// Cost progress as ratio of today vs (today + previous), clamped to 0-1
    public var costProgress: Double {
        let total = Double(truncating: (today.totalCost + previous.totalCost) as NSDecimalNumber)
        guard total > 0 else { return 0 }
        return Double(truncating: today.totalCost as NSDecimalNumber) / total
    }

    /// Token progress as ratio of today vs (today + previous), clamped to 0-1
    public var tokenProgress: Double {
        let total = today.totalTokens + previous.totalTokens
        guard total > 0 else { return 0 }
        return Double(today.totalTokens) / Double(total)
    }

    /// Time progress as ratio of today vs (today + previous), clamped to 0-1
    public var timeProgress: Double {
        let total = today.workingTime + previous.workingTime
        guard total > 0 else { return 0 }
        return today.workingTime / total
    }
}
