import Foundation

/// Formatted quota value for the menu bar percentage label.
public struct MenuBarPercentageDisplay: Sendable, Equatable {
    public let text: String
    public let status: QuotaStatus
    public let quota: UsageQuota

    public init(
        quota: UsageQuota,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) {
        self.quota = quota
        self.text = "\(Int(quota.displayPercent(mode: mode)))%"
        self.status = burnRateWarningEnabled
            ? quota.paceAwareStatus(burnRateThreshold: burnRateThreshold)
            : quota.status
    }
}
