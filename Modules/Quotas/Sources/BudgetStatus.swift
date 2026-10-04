import Foundation

/// Represents the budget status for cost-based tracking.
/// Similar to QuotaStatus but for budget thresholds instead of percentage remaining.
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md) — becomes `Budget` — the user's ceiling on a `Cost` — and its
///   ON TRACK · NEAR LIMIT · OVER BUDGET judgement (§0.1).
public enum BudgetStatus: String, Sendable, Equatable, Hashable, Comparable {
    /// Cost is below 80% of budget
    case withinBudget
    /// Cost is between 80-100% of budget
    case approachingLimit
    /// Cost exceeds 100% of budget
    case overBudget

    // MARK: - Factory Method

    /// Determines budget status based on current cost and budget threshold.
    /// - Parameters:
    ///   - cost: The current total cost
    ///   - budget: The budget threshold
    /// - Returns: The appropriate budget status
    public static func from(cost: Decimal, budget: Decimal) -> BudgetStatus {
        guard budget > 0 else { return .withinBudget }

        let percentUsed = (cost / budget) * 100

        if percentUsed >= 100 {
            return .overBudget
        } else if percentUsed >= 80 {
            return .approachingLimit
        } else {
            return .withinBudget
        }
    }

    // MARK: - Display Properties

    /// Text to display on status badges
    public var badgeText: String {
        switch self {
        case .withinBudget: return "ON TRACK"
        case .approachingLimit: return "NEAR LIMIT"
        case .overBudget: return "OVER BUDGET"
        }
    }

    /// Whether this status requires user attention
    public var needsAttention: Bool {
        switch self {
        case .withinBudget: return false
        case .approachingLimit, .overBudget: return true
        }
    }

    /// Severity level for comparison (higher = worse)
    public var severity: Int {
        switch self {
        case .withinBudget: return 0
        case .approachingLimit: return 1
        case .overBudget: return 2
        }
    }

    // MARK: - Comparable

    public static func < (lhs: BudgetStatus, rhs: BudgetStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}
