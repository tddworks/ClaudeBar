import Foundation
import ClaudeBarKit

extension UsageQuota {
    /// A quota in today's shape. A balance with no ceiling written as 100% reads as money.
    public convenience init(
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
        self.init(
            percentRemaining: percentRemaining,
            quotaType: quotaType,
            providerId: providerId,
            resetsAtSeconds: resetsAt.map(\.kernelSeconds).kotlin,
            resetText: resetText,
            windowSeconds: windowDuration.kotlin,
            dollarRemainingNanos: dollarRemaining.map(\.nanos).kotlin,
            dollarUsedNanos: dollarUsed.map(\.nanos).kotlin,
            dollarCapNanos: dollarCap.map(\.nanos).kotlin,
            group: group,
            compactTitle: compactTitle,
            menuBarTitle: menuBarTitle,
            currency: currency
        )
    }

    /// A quota in the model's shape: what is left, and the window it refills in.
    public convenience init(
        left: Left,
        quotaType: QuotaType,
        providerId: String,
        resetsAt: Date? = nil,
        resetText: String? = nil,
        windowDuration: TimeInterval? = nil,
        group: String? = nil,
        compactTitle: String? = nil,
        menuBarTitle: String? = nil
    ) {
        self.init(
            left: left,
            quotaType: quotaType,
            providerId: providerId,
            resetsAtSeconds: resetsAt.map(\.kernelSeconds).kotlin,
            resetText: resetText,
            windowSeconds: windowDuration.kotlin,
            group: group,
            compactTitle: compactTitle,
            menuBarTitle: menuBarTitle
        )
    }

    public static func == (lhs: UsageQuota, rhs: UsageQuota) -> Bool { lhs.isEqual(rhs) }

    // MARK: - Foundation views

    /// When this quota resets, if known.
    public var resetsAt: Date? { resetsAtSeconds.swift.map(Date.init(kernelSeconds:)) }
    /// The window's length in seconds, when the data source states it.
    public var windowDuration: TimeInterval? { windowSeconds.swift }
    public var dollarRemaining: Decimal? { dollarRemainingNanos.swift.map(Decimal.init(nanos:)) }
    public var dollarUsed: Decimal? { dollarUsedNanos.swift.map(Decimal.init(nanos:)) }
    public var dollarCap: Decimal? { dollarCapNanos.swift.map(Decimal.init(nanos:)) }

    /// The percentage left — `nil` for a balance with no ceiling, which has none.
    public var percentLeft: Double? { percentLeftOrNull.swift }

    // MARK: - Laws read now (the kernel takes the clock)

    public var timeUntilReset: TimeInterval? { timeUntilReset(nowSeconds: KernelClock.now).swift }
    public var percentTimeElapsed: Double? { percentTimeElapsed(nowSeconds: KernelClock.now).swift }
    public var pacePercent: Double? { pacePercent(nowSeconds: KernelClock.now).swift }
    public var burnRate: Double? { burnRate(nowSeconds: KernelClock.now).swift }
    public var pace: UsagePace { pace(nowSeconds: KernelClock.now) }
    public var paceInsight: String? { paceInsight(nowSeconds: KernelClock.now) }
    public var paceLevel: PaceLevel? { paceLevel(nowSeconds: KernelClock.now) }
    public var compactResetTime: String? { compactResetTime(nowSeconds: KernelClock.now) }
    public var resetTimestampDescription: String? { resetTimestampDescription(nowSeconds: KernelClock.now) }
    public var resetDescription: String? { resetDescription(nowSeconds: KernelClock.now) }

    /// This quota's status under the person's policy.
    public func status(under policy: StatusPolicy) -> QuotaStatus {
        status(under: policy, nowSeconds: KernelClock.now)
    }

    /// Pace-aware status when the window is known; absolute thresholds otherwise.
    public func paceAwareStatus(burnRateThreshold: Double) -> QuotaStatus {
        paceAwareStatus(burnRateThreshold: burnRateThreshold, nowSeconds: KernelClock.now)
    }

    /// The display symbol for an ISO 4217 code ("USD" → "$").
    public static func currencySymbol(for code: String) -> String {
        UsageQuota.companion.currencySymbol(code: code)
    }

    // MARK: - Presentation (page state, CANONICAL_MODEL §6)

    /// "$50.00", "¥110.00"; nil for percentage quotas.
    public var formattedDollarRemaining: String? {
        guard let dollarRemaining else { return nil }
        let amount = NSDecimalNumber(decimal: dollarRemaining).doubleValue
        let symbol = currency.map(Self.currencySymbol(for:)) ?? "$"
        return String(format: "%@%.2f", symbol, amount)
    }

    /// "$1,234.56" for a capped spend meter.
    public var formattedDollarUsed: String? { formatDollars(dollarUsed, minimumFractionDigits: 2) }

    /// "$500" for a capped spend meter.
    public var formattedDollarCap: String? { formatDollars(dollarCap, minimumFractionDigits: 0) }

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
}

extension UsageQuota: @retroactive Comparable {
    public static func < (lhs: UsageQuota, rhs: UsageQuota) -> Bool {
        lhs.percentRemaining < rhs.percentRemaining
    }
}

public extension Collection where Element == UsageQuota {
    /// One reset countdown when every quota resets within 60 seconds of the others.
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
