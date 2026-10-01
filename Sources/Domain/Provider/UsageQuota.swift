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

    /// The actual duration of this quota's window in seconds, when the data
    /// source reports it (e.g. Oh My Pi's `window.durationMs`). Pace math
    /// falls back to `quotaType.duration` when nil.
    public let windowDuration: TimeInterval?

    /// Dollar balance remaining for credit-based quotas with no cap (e.g., "$50 remaining").
    /// nil for percentage-based quotas that have a known total.
    public let dollarRemaining: Decimal?

    /// Dollars spent for a capped spend meter.
    /// Co-occurs with `dollarCap`; nil for percentage and balance meters.
    public let dollarUsed: Decimal?

    /// Dollar cap for a capped spend meter.
    /// Co-occurs with `dollarUsed`; nil for percentage and balance meters.
    public let dollarCap: Decimal?

    /// Section this quota belongs to when an aggregating provider spans
    /// several upstream accounts (e.g. "Claude", "Claude · work").
    /// nil for providers whose quotas render as one flat list.
    public let group: String?

    /// Short card title used when the quota renders inside its group's
    /// section (e.g. "5h", "Spark 7d"). The UI falls back to
    /// `quotaType.displayName` when nil. The full label stays in
    /// `quotaType` so persisted quota keys and the menu bar are unaffected.
    public let compactTitle: String?

    /// Menu-bar window title used when this quota renders as one of two
    /// joined/stacked windows (e.g. "Claude 7d · jkjk987…"). Probes set it
    /// when the full label is too wide for the menu bar — typically a long
    /// account discriminator. The menu bar falls back to
    /// `quotaType.shortLabel` when nil. The full label stays in `quotaType`
    /// so persisted quota keys are unaffected.
    public let menuBarTitle: String?

    /// ISO 4217 currency code for dollar-based quotas (e.g. "USD", "CNY").
    /// nil means USD (the default). Used by `formattedDollarRemaining` to pick
    /// the display symbol; ignored for percentage-based quotas.
    public let currency: String?

    // MARK: - Initialization

    public init(
        percentRemaining: Double,
        quotaType: QuotaType,
        providerId: String,
        resetsAt: Date? = nil,
        resetText: String? = nil,
        windowDuration: TimeInterval? = nil,
        dollarRemaining: Decimal? = nil,
        dollarUsed: Decimal? = nil,
        dollarCap: Decimal? = nil,
        group: String? = nil,
        compactTitle: String? = nil,
        menuBarTitle: String? = nil,
        currency: String? = nil
    ) {
        self.percentRemaining = min(100, percentRemaining)  // Allow negative, cap at 100
        self.quotaType = quotaType
        self.providerId = providerId
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.windowDuration = windowDuration
        self.dollarRemaining = dollarRemaining
        self.dollarUsed = dollarUsed
        self.dollarCap = dollarCap
        self.group = group
        self.compactTitle = compactTitle
        self.menuBarTitle = menuBarTitle
        self.currency = currency
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

    /// Formatted balance remaining string (e.g., "$50.00", "¥110.00"), nil for percentage-based quotas.
    /// The symbol follows `currency` (default "$" when nil or USD).
    public var formattedDollarRemaining: String? {
        guard let dollarRemaining else { return nil }
        let amount = NSDecimalNumber(decimal: dollarRemaining).doubleValue
        let symbol = currency.map(Self.currencySymbol(for:)) ?? "$"
        return String(format: "%@%.2f", symbol, amount)
    }

    /// Formatted spend amount for capped monetary quotas (e.g. "$1,234.56").
    public var formattedDollarUsed: String? {
        formatDollars(dollarUsed, minimumFractionDigits: 2)
    }

    /// Formatted cap for capped monetary quotas (e.g. "$500").
    public var formattedDollarCap: String? {
        formatDollars(dollarCap, minimumFractionDigits: 0)
    }

    private func formatDollars(_ amount: Decimal?, minimumFractionDigits: Int) -> String? {
        guard let amount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "$\(value)"
    }

    /// Maps an ISO 4217 currency code to its display symbol (e.g., "USD" → "$", "CNY" → "¥").
    /// Unknown codes fall back to the uppercased code with a trailing space.
    public static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD", "US", "US$": return "$"
        case "CNY", "CNH", "RMB", "CN", "¥": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "HKD": return "HK$"
        case "KRW": return "₩"
        case "SGD": return "S$"
        default: return code.uppercased() + " "
        }
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

    /// Returns the percentage to use for progress bar width.
    ///
    /// The bar shares the headline number's scale so the two never disagree:
    /// `.remaining` and `.pace` start full and drain from the right as quota is
    /// consumed, `.used` fills from the left. Bar color still follows remaining/status.
    public func displayProgressPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining, .pace: percentRemaining
        case .used: percentUsed
        }
    }

    /// Returns the expected progress bar position based on time elapsed.
    /// This is where the bar would sit if usage were spread evenly across the
    /// window, on the same scale as the fill it annotates. Returns nil when
    /// reset time is unknown.
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
        let totalDuration = windowDuration ?? quotaType.duration.seconds
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

    /// Tooltip copy explaining the pace tick mark under the progress bar.
    /// Mode-aware: describes where the bar would sit if usage were spread
    /// evenly across the window. Returns nil when reset time is unknown.
    public func paceTickHelp(mode: UsageDisplayMode) -> String? {
        guard let expected = expectedProgressPercent(mode: mode) else { return nil }
        let base = switch mode {
        case .used:
            "Pace marker: steady usage would have used ~\(Int(expected.rounded()))% by now"
        case .remaining, .pace:
            "Pace marker: steady usage would leave ~\(Int(expected.rounded()))% remaining by now"
        }
        guard let insight = paceInsight else { return base + "." }
        return base + " — " + insight.prefix(1).lowercased() + insight.dropFirst() + "."
    }

    /// Time until this quota resets (if known)
    public var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSinceNow)
    }

    /// Compact reset duration for the menu bar label (e.g., "1d", "3:58", "45m").
    /// Hours use "H:MM" so the label stays short without hiding up to 59
    /// minutes behind a bare "3h"; days keep a single unit since sub-day
    /// precision matters less at that range. "soon" under a minute; nil when
    /// reset time is unknown.
    public var compactResetTime: String? {
        guard let timeUntilReset else { return nil }
        let s = Int(timeUntilReset)
        if s >= 86400 { return "\(s / 86400)d" }
        if s >= 3600  { return String(format: "%d:%02d", s / 3600, (s % 3600) / 60) }
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

public extension Collection where Element == UsageQuota {
    /// Shared reset countdown when every quota resets at the same time.
    ///
    /// Returns a single `resetTimestampDescription` when there are at least two
    /// quotas, every quota has a `resetsAt`, and those timestamps sit within
    /// 60 seconds of each other. Otherwise nil — callers should keep per-card clocks.
    func sharedResetDescription() -> String? {
        guard count >= 2 else { return nil }
        let dates = compactMap(\.resetsAt)
        guard dates.count == count,
              let earliest = dates.min(),
              let latest = dates.max(),
              latest.timeIntervalSince(earliest) <= 60
        else { return nil }
        return first?.resetTimestampDescription
    }
}
