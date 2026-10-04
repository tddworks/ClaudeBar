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

    /// Creates a pace-aware status using burn rate (usage% / timeElapsed%).
    /// Burn rate > threshold means consuming faster than the period can sustain.
    /// Critical and depleted thresholds are always absolute (safety net).
    /// Falls back to absolute thresholds when time elapsed is 0 (start of period).
    ///
    /// - Parameters:
    ///   - percentRemaining: The percentage of quota remaining (0-100)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    ///   - burnRateThreshold: The multiplier above which a warning fires (e.g., 1.5 = 50% faster than sustainable)
    public static func from(
        percentRemaining: Double,
        percentTimeElapsed: Double,
        burnRateThreshold: Double
    ) -> QuotaStatus {
        // Absolute safety nets — always apply regardless of pace
        if percentRemaining <= 0 { return .depleted }
        if percentRemaining < 20 { return .critical }

        // At start of period or no time data, fall back to absolute thresholds
        guard percentTimeElapsed > 0 else {
            return from(percentRemaining: percentRemaining)
        }

        let percentUsed = 100 - percentRemaining
        let burnRate = percentUsed / percentTimeElapsed

        // Only warn if burn rate exceeds threshold AND remaining is below 50%
        // (no point warning about high burn rate when there's plenty of quota left)
        if burnRate > burnRateThreshold && percentRemaining < 50 {
            return .warning
        }

        return .healthy
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
