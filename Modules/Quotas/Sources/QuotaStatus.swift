import Foundation

/// Represents the health status of a usage quota.
/// Rich domain model - status is determined by business rules, not UI logic.
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md) — becomes `Status`, derived from `Quota.left` under a `StatusPolicy`:
///   depleted at 0 and critical under 20 whatever the policy (§5).
public enum QuotaStatus: Sendable, Equatable, Hashable, Comparable {
    /// Quota has remaining capacity (>50%)
    case healthy
    /// Quota is getting low (20-50%)
    case warning
    /// Quota is almost exhausted (<20%)
    case critical
    /// Quota is completely exhausted (0%)
    case depleted

    // MARK: - Factory Methods

    /// The share of the window gone before the pace-aware status projects:
    /// a warning is louder than a pace, so it waits for more of the window.
    private static let warnFloor: Double = 15

    /// Creates a status based on the percentage remaining.
    /// This encapsulates the business rules for status thresholds.
    public static func from(percentRemaining: Double) -> QuotaStatus {
        switch percentRemaining {
        case ...0:
            .depleted
        case 0..<20:
            .critical
        case 20..<50:
            .warning
        default:
            .healthy
        }
    }

    /// Creates a pace-aware status from the projected end-of-period usage
    /// (usage% / timeElapsed%): under 70% healthy, 70-90% warning, 90%+ critical.
    /// Before 15% of the period has elapsed, once it is over, or with nothing
    /// used yet, falls back to used% thresholds: under 70% healthy, 70-90%
    /// warning, 90%+ critical. Depleted stays absolute.
    ///
    /// - Parameters:
    ///   - percentRemaining: The percentage of quota remaining (0-100)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    ///   - burnRateThreshold: Unused; kept for source compatibility with the burn-rate setting
    public static func from(
        percentRemaining: Double,
        percentTimeElapsed: Double,
        burnRateThreshold: Double
    ) -> QuotaStatus {
        if percentRemaining <= 0 { return .depleted }

        let percentUsed = 100 - percentRemaining

        // Project end-of-period usage from the quota's one rate, once enough of
        // the period has elapsed to warn on it: `warnFloor` is when to warn,
        // later than the rate's noise floor so an alarm never fires on a
        // window's first minutes.
        if percentTimeElapsed >= warnFloor, percentUsed > 0,
           let rate = SpendRate(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed) {
            switch rate.value {
            case ..<0.70: return .healthy
            case 0.70..<0.90: return .warning
            default: return .critical
            }
        }

        switch percentUsed {
        case ..<70: return .healthy
        case 70..<90: return .warning
        default: return .critical
        }
    }

    // MARK: - Status Behavior

    /// Whether this status indicates a problem that needs attention
    public var needsAttention: Bool {
        switch self {
        case .healthy:
            false
        case .warning, .critical, .depleted:
            true
        }
    }

    /// The severity level (higher = more severe)
    private var severity: Int {
        switch self {
        case .healthy: 0
        case .warning: 1
        case .critical: 2
        case .depleted: 3
        }
    }

    public static func < (lhs: QuotaStatus, rhs: QuotaStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}
