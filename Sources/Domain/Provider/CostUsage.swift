import Foundation

/// Represents cost-based usage data for Claude accounts.
/// Used for API accounts (pay-per-use) and Pro accounts with Extra usage enabled.
public struct CostUsage: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case apiCost
        case extraUsage
    }

    /// Whether this represents general API cost or subscription Extra usage.
    public let kind: Kind

    /// The total cost/spent amount in dollars
    public let totalCost: Decimal

    /// The budget limit (for Pro accounts with Extra usage, e.g., $20.00)
    /// nil for API accounts that don't have a fixed budget
    public let budget: Decimal?

    /// Total time spent on API calls
    public let apiDuration: TimeInterval

    /// Total wall clock time (includes thinking/typing time)
    public let wallDuration: TimeInterval

    /// Number of lines of code added
    public let linesAdded: Int

    /// Number of lines of code removed
    public let linesRemoved: Int

    /// The provider ID this cost belongs to (e.g., "claude")
    public let providerId: String

    /// When this usage data was captured
    public let capturedAt: Date

    /// When this cost usage resets (for Pro Extra usage)
    public let resetsAt: Date?

    /// Human-readable reset text (e.g., "Resets Jan 1, 2026")
    public let resetText: String?

    // MARK: - Initialization

    public init(
        totalCost: Decimal,
        budget: Decimal? = nil,
        apiDuration: TimeInterval,
        wallDuration: TimeInterval = 0,
        linesAdded: Int = 0,
        linesRemoved: Int = 0,
        providerId: String,
        kind: Kind = .apiCost,
        capturedAt: Date = Date(),
        resetsAt: Date? = nil,
        resetText: String? = nil
    ) {
        self.kind = kind
        self.totalCost = totalCost
        self.budget = budget
        self.apiDuration = apiDuration
        self.wallDuration = wallDuration
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.providerId = providerId
        self.capturedAt = capturedAt
        self.resetsAt = resetsAt
        self.resetText = resetText
    }

    // MARK: - Formatting

    /// Formatted cost string (e.g., "$0.55")
    public var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalCost as NSDecimalNumber) ?? "$\(totalCost)"
    }

    /// Formatted API duration (e.g., "6m 19.7s")
    public var formattedApiDuration: String {
        formatDuration(apiDuration)
    }

    /// Formatted wall duration (e.g., "6h 33m 10.2s")
    public var formattedWallDuration: String {
        formatDuration(wallDuration)
    }

    /// Formatted code changes (e.g., "+10 / -5 lines")
    public var formattedCodeChanges: String {
        "+\(linesAdded) / -\(linesRemoved) lines"
    }

    // MARK: - Budget Calculation

    /// Calculates the budget status based on the given budget threshold
    public func budgetStatus(budget: Decimal) -> BudgetStatus {
        BudgetStatus.from(cost: totalCost, budget: budget)
    }

    /// Calculates budget status using the built-in budget (for Pro Extra usage)
    public var budgetStatusFromBuiltIn: BudgetStatus? {
        guard let budget else { return nil }
        return BudgetStatus.from(cost: totalCost, budget: budget)
    }

    /// Calculates the percentage of budget used
    public func budgetPercentUsed(budget: Decimal) -> Double {
        guard budget > 0 else { return 0 }
        let percentage = (totalCost / budget) * 100
        return Double(truncating: percentage as NSDecimalNumber)
    }

    /// Calculates percentage used from built-in budget (for Pro Extra usage)
    public var budgetPercentUsedFromBuiltIn: Double? {
        guard let budget else { return nil }
        return budgetPercentUsed(budget: budget)
    }

    /// The unspent built-in budget, floored at zero.
    public var budgetRemaining: Decimal? {
        guard let budget else { return nil }
        return max(0, budget - totalCost)
    }

    /// Formatted budget string (e.g., "$20.00")
    public var formattedBudget: String? {
        guard let budget else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: budget as NSDecimalNumber) ?? "$\(budget)"
    }

    // MARK: - Private Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)

        if hours > 0 {
            return String(format: "%dh %dm %.1fs", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %.1fs", minutes, seconds)
        } else {
            return String(format: "%.1fs", seconds)
        }
    }
}
