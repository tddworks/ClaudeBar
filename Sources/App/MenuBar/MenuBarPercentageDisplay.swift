import Quotas
import DataSources
import Providers
import Foundation

/// Formatted quota value for the menu bar percentage label.
public struct MenuBarPercentageDisplay: Sendable, Equatable {
    public let text: String
    public let status: QuotaStatus
    public let quota: UsageQuota

    public init(
        quota: UsageQuota,
        mode: UsageDisplayMode,
        policy: StatusPolicy = .absolute
    ) {
        self.quota = quota
        // A balance has no percentage: the menu bar shows its money.
        self.text = quota.isBalance
            ? (quota.formattedDollarRemaining ?? "—")
            : "\(Int(quota.displayPercent(mode: mode)))%"
        self.status = quota.status(under: policy)
    }
}
