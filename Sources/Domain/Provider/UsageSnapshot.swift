import Foundation

/// Represents a point-in-time snapshot of usage quotas for an AI provider.
/// This is an aggregate root that collects all quota information for a provider.
public struct UsageSnapshot: Sendable, Equatable {
    /// The provider ID this snapshot belongs to (e.g., "claude", "codex", "gemini")
    public let providerId: String

    /// All quotas captured in this snapshot (empty for API accounts)
    public let quotas: [UsageQuota]

    /// When this snapshot was captured
    public let capturedAt: Date

    /// Optional account information
    public let accountEmail: String?
    public let accountOrganization: String?
    public let loginMethod: String?

    /// The account tier (e.g., Claude Max, Pro, or custom tier from other providers)
    public let accountTier: AccountTier?

    /// Cost-based usage data (for Claude API accounts)
    public let costUsage: CostUsage?

    /// Bedrock usage summary (for AWS Bedrock provider)
    public let bedrockUsage: BedrockUsageSummary?

    /// Daily usage report from local session JSONL analysis (e.g., Claude Code)
    public let dailyUsageReport: DailyUsageReport?

    /// Generic metrics from extension probes
    public let extensionMetrics: [ExtensionMetric]?

    // MARK: - Initialization

    public init(
        providerId: String,
        quotas: [UsageQuota],
        capturedAt: Date,
        accountEmail: String? = nil,
        accountOrganization: String? = nil,
        loginMethod: String? = nil,
        accountTier: AccountTier? = nil,
        costUsage: CostUsage? = nil,
        bedrockUsage: BedrockUsageSummary? = nil,
        dailyUsageReport: DailyUsageReport? = nil,
        extensionMetrics: [ExtensionMetric]? = nil
    ) {
        self.providerId = providerId
        self.quotas = quotas
        self.capturedAt = capturedAt
        self.accountEmail = accountEmail
        self.accountOrganization = accountOrganization
        self.loginMethod = loginMethod
        self.accountTier = accountTier
        self.costUsage = costUsage
        self.bedrockUsage = bedrockUsage
        self.dailyUsageReport = dailyUsageReport
        self.extensionMetrics = extensionMetrics
    }

    // MARK: - Domain Queries

    /// Finds a specific quota type from this snapshot
    public func quota(for type: QuotaType) -> UsageQuota? {
        quotas.first { $0.quotaType == type }
    }

    /// Finds a quota by its persisted quota key.
    public func quota(forKey key: String) -> UsageQuota? {
        guard let quotaType = QuotaType(quotaKey: key) else { return nil }
        return quota(for: quotaType)
    }

    /// The session quota if available
    public var sessionQuota: UsageQuota? {
        quota(for: .session)
    }

    /// The weekly quota if available
    public var weeklyQuota: UsageQuota? {
        quota(for: .weekly)
    }

    /// All model-specific quotas
    public var modelSpecificQuotas: [UsageQuota] {
        quotas.filter { quota in
            if case .modelSpecific = quota.quotaType {
                return true
            }
            return false
        }
    }

    /// Whether any quota or metric carries group metadata (aggregating
    /// providers like Oh My Pi tag rows with their upstream account).
    public var hasQuotaGroups: Bool {
        quotas.contains { $0.group != nil }
            || (extensionMetrics ?? []).contains { $0.group != nil }
    }

    /// Quotas bucketed by their group, preserving first-appearance order.
    /// Ungrouped quotas form one leading unnamed group. Grouped extension
    /// metrics (accounts without usable quota data) become note-only
    /// sections after the quota sections, or attach to a matching section.
    public var quotaGroups: [QuotaGroup] {
        var order: [String] = []
        var buckets: [String: [UsageQuota]] = [:]
        for quota in quotas {
            let key = quota.group ?? ""
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(quota)
        }

        var notes: [String: String] = [:]
        for metric in extensionMetrics ?? [] {
            guard let group = metric.group else { continue }
            if buckets[group] == nil, notes[group] == nil { order.append(group) }
            if let existing = notes[group] {
                notes[group] = "\(existing)\n\(metric.value)"
            } else {
                notes[group] = metric.value
            }
        }

        return order.map { key in
            QuotaGroup(
                title: key.isEmpty ? nil : key,
                quotas: buckets[key] ?? [],
                note: notes[key]
            )
        }
    }

    /// The overall status is the worst status among all quotas.
    /// This is a domain rule: overall health reflects the most critical issue.
    public var overallStatus: QuotaStatus {
        quotas.map(\.status).max() ?? .healthy
    }

    /// The overall status using burn rate when enabled.
    /// Falls back to absolute thresholds for quotas without reset time.
    public func paceAwareOverallStatus(burnRateThreshold: Double) -> QuotaStatus {
        quotas.map { $0.paceAwareStatus(burnRateThreshold: burnRateThreshold) }.max() ?? .healthy
    }

    /// The quota with the lowest remaining percentage.
    /// Useful for determining which limit to highlight.
    public var lowestQuota: UsageQuota? {
        quotas.min(by: { $0.percentRemaining < $1.percentRemaining })
    }

    // MARK: - Freshness

    /// How many seconds ago this snapshot was captured
    public var age: TimeInterval {
        Date().timeIntervalSince(capturedAt)
    }

    /// Whether this snapshot is considered stale (older than 5 minutes)
    public var isStale: Bool {
        age > 300 // 5 minutes
    }

    /// Human-readable age description
    public var ageDescription: String {
        let seconds = Int(age)
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }

    // MARK: - Empty Snapshot

    /// Creates an empty snapshot for when no data is available
    public static func empty(for providerId: String) -> UsageSnapshot {
        UsageSnapshot(providerId: providerId, quotas: [], capturedAt: Date())
    }
}

/// One section of quotas belonging to a single upstream account, produced
/// by aggregating providers (e.g. Oh My Pi). `title` is nil for the
/// unnamed bucket of ungrouped quotas.
public struct QuotaGroup: Sendable, Equatable, Identifiable {
    public let title: String?
    public let quotas: [UsageQuota]

    /// Inline annotation for sections without usable quota data
    /// (e.g. "No usage reported"). See `notePlacement` for where it
    /// renders.
    public let note: String?

    public var id: String { title ?? "" }

    /// The most critical status within this group — shown while collapsed.
    public var worstStatus: QuotaStatus {
        quotas.map(\.status).max() ?? .healthy
    }

    /// The quota with the least headroom — summarized while collapsed.
    public var lowestQuota: UsageQuota? {
        quotas.min(by: { $0.percentRemaining < $1.percentRemaining })
    }

    /// Where a group's note renders. Note-only sections have no cards
    /// to collapse, so the note doubles as the header summary; sections
    /// that also carry quotas show the note as its own row above the
    /// cards — it must never be silently dropped.
    public enum NotePlacement: Sendable, Equatable {
        case headerInline(String)
        case row(String)
    }

    /// The presentation decision for `note`, nil when there is none.
    public var notePlacement: NotePlacement? {
        guard let note else { return nil }
        return quotas.isEmpty ? .headerInline(note) : .row(note)
    }

    public init(title: String?, quotas: [UsageQuota], note: String? = nil) {
        self.title = title
        self.quotas = quotas
        self.note = note
    }
}
