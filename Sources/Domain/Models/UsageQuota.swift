import Foundation

/// Represents a single usage quota measurement for an AI provider.
/// This is a rich domain model that encapsulates quota-related behavior.
public struct UsageQuota: Sendable, Equatable, Hashable, Comparable {
    /// The percentage of quota remaining (0-100)
    public let percentRemaining: Double

    /// The type of quota (session, weekly, model-specific)
    public let quotaType: QuotaType

    /// The AI provider this quota belongs to
    public let provider: AIProvider

    /// When this quota will reset (if known)
    public let resetsAt: Date?

    // MARK: - Initialization

    public init(
        percentRemaining: Double,
        quotaType: QuotaType,
        provider: AIProvider,
        resetsAt: Date? = nil
    ) {
        self.percentRemaining = max(0, min(100, percentRemaining))
        self.quotaType = quotaType
        self.provider = provider
        self.resetsAt = resetsAt
    }

    // MARK: - Domain Behavior

    /// The current health status based on percentage remaining.
    /// This is a domain rule: status is determined by business thresholds.
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    /// The percentage that has been used (0-100)
    public var percentUsed: Double {
        100 - percentRemaining
    }

    /// Whether this quota is completely exhausted
    public var isDepleted: Bool {
        percentRemaining <= 0
    }

    /// Whether this quota needs attention (warning, critical, or depleted)
    public var needsAttention: Bool {
        status.needsAttention
    }

    /// Time until this quota resets (if known)
    public var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSinceNow)
    }

    /// Human-readable description of time until reset
    public var resetDescription: String? {
        guard let timeUntilReset else { return nil }

        let hours = Int(timeUntilReset / 3600)
        let minutes = Int((timeUntilReset.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "Resets in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Resets in \(minutes)m"
        } else {
            return "Resets soon"
        }
    }

    // MARK: - Comparable

    public static func < (lhs: UsageQuota, rhs: UsageQuota) -> Bool {
        lhs.percentRemaining < rhs.percentRemaining
    }
}
