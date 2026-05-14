import Foundation

/// Represents a single usage quota measurement for an AI provider.
/// This is a rich domain model that encapsulates quota-related behavior.
public struct UsageQuota: Sendable, Equatable, Hashable, Comparable {
    /// The percentage of quota remaining (can be negative when over quota, capped at 100)
    public let percentRemaining: Double

    /// The type of quota (session, weekly, model-specific)
    public let quotaType: QuotaType

    /// The provider ID this quota belongs to (e.g., "claude", "codex", "gemini")
    public let providerId: String

    /// When this quota will reset (if known)
    public let resetsAt: Date?

    /// Raw reset text from CLI (e.g., "Resets 11am", "Resets Jan 15")
    public let resetText: String?

    /// Dollar balance remaining for credit-based quotas with no cap (e.g., "$50 remaining").
    /// nil for percentage-based quotas that have a known total.
    public let dollarRemaining: Decimal?

    // MARK: - Initialization

    public init(
        percentRemaining: Double,
        quotaType: QuotaType,
        providerId: String,
        resetsAt: Date? = nil,
        resetText: String? = nil,
        dollarRemaining: Decimal? = nil
    ) {
        self.percentRemaining = min(100, percentRemaining)  // Allow negative, cap at 100
        self.quotaType = quotaType
        self.providerId = providerId
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.dollarRemaining = dollarRemaining
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

    /// Whether this quota is dollar-based (credit balance with no percentage cap)
    public var isDollarBased: Bool {
        dollarRemaining != nil
    }

    /// Formatted dollar remaining string (e.g., "$50.00"), nil for percentage-based quotas
    public var formattedDollarRemaining: String? {
        guard let dollarRemaining else { return nil }
        let amount = NSDecimalNumber(decimal: dollarRemaining).doubleValue
        return String(format: "$%.2f", amount)
    }

    /// Whether this quota needs attention (warning, critical, or depleted)
    public var needsAttention: Bool {
        status.needsAttention
    }

    /// Returns the display percentage based on the display mode.
    /// - In `.remaining` mode: returns `percentRemaining`
    /// - In `.used` mode: returns `percentUsed` (100 - percentRemaining)
    /// - In `.pace` mode: returns `percentRemaining` (familiar number, with pace context from badge + insight)
    public func displayPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining: percentRemaining
        case .used: percentUsed
        case .pace: percentRemaining
        }
    }

    /// Returns the percentage to use for progress bar width based on the display mode.
    /// - In `.remaining` mode: bar fills from right to left as quota depletes
    /// - In `.used` mode: bar fills from left to right as quota is consumed
    /// - In `.pace` mode: bar shows remaining (same as remaining mode)
    public func displayProgressPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining: percentRemaining
        case .used: percentUsed
        case .pace: percentRemaining
        }
    }

    /// Returns the expected progress bar position based on time elapsed and display mode.
    /// This represents where the bar "should be" if usage were perfectly on pace.
    /// Returns nil when reset time is unknown.
    public func expectedProgressPercent(mode: UsageDisplayMode) -> Double? {
        guard let percentTimeElapsed else { return nil }
        switch mode {
        case .remaining, .pace: return 100 - percentTimeElapsed
        case .used: return percentTimeElapsed
        }
    }

    // MARK: - Burn Rate

    /// The burn rate: how fast quota is being consumed relative to time elapsed.
    /// A burn rate of 1.0 means consuming exactly on pace.
    /// A burn rate of 2.0 means consuming 2x faster than sustainable.
    /// Returns nil when reset time is unknown.
    public var burnRate: Double? {
        guard let percentTimeElapsed, percentTimeElapsed > 0 else { return nil }
        return percentUsed / percentTimeElapsed
    }

    /// Returns quota status using burn rate when time information is available.
    /// Falls back to absolute thresholds when reset time is unknown.
    /// - Parameter burnRateThreshold: The multiplier above which a warning fires (e.g., 1.5)
    public func paceAwareStatus(burnRateThreshold: Double) -> QuotaStatus {
        guard let percentTimeElapsed else {
            return status // Fall back to absolute thresholds
        }
        return QuotaStatus.from(
            percentRemaining: percentRemaining,
            percentTimeElapsed: percentTimeElapsed,
            burnRateThreshold: burnRateThreshold
        )
    }

    // MARK: - Pace

    /// The percentage of the reset period that has elapsed (0-100), or nil if no reset time is known.
    ///
    /// Calculated as: `(totalDuration - timeUntilReset) / totalDuration * 100`
    public var percentTimeElapsed: Double? {
        guard let timeUntilReset else { return nil }
        let totalDuration = quotaType.duration.seconds
        guard totalDuration > 0 else { return nil }
        let elapsed = totalDuration - timeUntilReset
        return min(100, max(0, elapsed / totalDuration * 100))
    }

    /// The difference between actual usage and expected usage based on time elapsed.
    /// Positive means ahead (consuming faster), negative means behind (room to spare).
    /// Returns nil if time-based pace cannot be determined.
    public var pacePercent: Double? {
        guard let percentTimeElapsed else { return nil }
        return percentUsed - percentTimeElapsed
    }

    /// The pace classification for this quota.
    public var pace: UsagePace {
        guard let pacePercent, let percentTimeElapsed else { return .unknown }
        return UsagePace.from(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed)
    }

    /// A human-readable insight about the pace deviation (e.g., "37% below expected usage").
    /// Returns nil when pace cannot be determined.
    public var paceInsight: String? {
        guard let pacePercent, pace != .unknown else { return nil }
        let delta = Int(abs(pacePercent))
        switch pace {
        case .behind: return "\(delta)% below expected usage"
        case .ahead: return "\(delta)% above expected usage"
        case .onPace: return "Right on track"
        case .unknown: return nil
        }
    }

    /// Time until this quota resets (if known)
    public var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSinceNow)
    }

    /// Compact reset duration for the menu bar label (e.g., "1d", "3h 30m", "45m").
    /// Single largest non-zero unit ("Xd", "Xh", "Xm"); "soon" under a
    /// minute; nil when reset time is unknown. Smaller-unit precision is
    /// intentionally dropped to keep the menu bar label short.
    public var compactResetTime: String? {
        guard let timeUntilReset else { return nil }
        let s = Int(timeUntilReset)
        if s >= 86400 { return "\(s / 86400)d" }
        if s >= 3600  { return "\(s / 3600)h" }
        if s >= 60    { return "\(s / 60)m" }
        return "soon"
    }

    /// Human-readable reset countdown with all components (e.g., "Resets in 2d 5h 30m")
    public var resetTimestampDescription: String? {
        guard let timeUntilReset else { return nil }

        let totalMinutes = Int(timeUntilReset / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }

        if parts.isEmpty { return "Resets soon" }
        return "Resets in \(parts.joined(separator: " "))"
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
