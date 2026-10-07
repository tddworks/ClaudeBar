import Foundation
import QuotaKernel

extension UsageSnapshot {
    public convenience init(
        providerId: String,
        quotas: [UsageQuota],
        capturedAt: Date,
        accountEmail: String? = nil,
        accountOrganization: String? = nil,
        loginMethod: String? = nil,
        accountTier: AccountTier? = nil,
        costUsage: CostUsage? = nil,
        dailyUsageReport: DailyUsageReport? = nil,
        extensionMetrics: [ExtensionMetric]? = nil
    ) {
        self.init(
            providerId: providerId,
            quotas: quotas,
            capturedAtSeconds: capturedAt.kernelSeconds,
            accountEmail: accountEmail,
            accountOrganization: accountOrganization,
            loginMethod: loginMethod,
            accountTier: accountTier,
            costUsage: costUsage,
            dailyUsageReport: dailyUsageReport,
            extensionMetrics: extensionMetrics
        )
    }

    public static func == (lhs: UsageSnapshot, rhs: UsageSnapshot) -> Bool { lhs.isEqual(rhs) }

    /// When this snapshot was captured.
    public var capturedAt: Date { Date(kernelSeconds: capturedAtSeconds) }

    public func quota(for type: QuotaType) -> UsageQuota? { quota(type: type) }
    public func quota(forKey key: String) -> UsageQuota? { quotaForKey(key: key) }

    /// The same usage without the quotas a person hid (#140).
    public func hiding(_ keys: Set<String>) -> UsageSnapshot { hiding(keys: keys) }

    public func paceAwareOverallStatus(burnRateThreshold: Double) -> QuotaStatus {
        paceAwareOverallStatus(burnRateThreshold: burnRateThreshold, nowSeconds: KernelClock.now)
    }

    /// The worst quota's status under the person's policy.
    public func overallStatus(under policy: StatusPolicy) -> QuotaStatus {
        overallStatus(under: policy, nowSeconds: KernelClock.now)
    }

    /// Seconds since capture.
    public var age: TimeInterval { age(nowSeconds: KernelClock.now) }
    /// Older than five minutes.
    public var isStale: Bool { isStale(nowSeconds: KernelClock.now) }
    /// "Just now", "4m ago", "2h ago".
    public var ageDescription: String { ageDescription(nowSeconds: KernelClock.now) }

    /// No usage yet.
    public static func empty(for providerId: String) -> UsageSnapshot {
        UsageSnapshot.companion.empty(providerId: providerId, nowSeconds: KernelClock.now)
    }
}

extension QuotaGroup: @retroactive Identifiable {
    public convenience init(title: String?, quotas: [UsageQuota]) {
        self.init(title: title, quotas: quotas, note: nil)
    }

    public static func == (lhs: QuotaGroup, rhs: QuotaGroup) -> Bool { lhs.isEqual(rhs) }

    public var id: String { title ?? "" }

    /// Where a group's note renders: in the header of a note-only section, else as its own row.
    public enum NotePlacement: Sendable, Equatable {
        case headerInline(String)
        case row(String)
    }

    public var notePlacement: NotePlacement? {
        guard let note else { return nil }
        return noteIsHeader ? .headerInline(note) : .row(note)
    }
}

extension AccountTier {
    public static var claudeMax: AccountTier { AccountTier.ClaudeMax.shared }
    public static var claudePro: AccountTier { AccountTier.ClaudePro.shared }
    public static var claudeApi: AccountTier { AccountTier.ClaudeApi.shared }
    public static func custom(_ badge: String) -> AccountTier { AccountTier.Custom(badge: badge) }

    public static func == (lhs: AccountTier, rhs: AccountTier) -> Bool { lhs.isEqual(rhs) }

    /// The plan, to `switch` on.
    public enum Shape: Equatable, Sendable {
        case claudeMax
        case claudePro
        case claudeApi
        case custom(String)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .claudeMax: .claudeMax
        case .claudePro: .claudePro
        case .claudeApi: .claudeApi
        case .custom(let tier): .custom(tier.badge)
        }
    }
}

@available(*, deprecated, renamed: "AccountTier")
public typealias ClaudeAccountType = AccountTier
