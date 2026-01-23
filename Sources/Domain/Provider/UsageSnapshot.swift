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
        bedrockUsage: BedrockUsageSummary? = nil
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
    }

    // MARK: - Domain Queries

    /// Finds a specific quota type from this snapshot
    public func quota(for type: QuotaType) -> UsageQuota? {
        quotas.first { $0.quotaType == type }
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

    /// The overall status is the worst status among all quotas.
    /// This is a domain rule: overall health reflects the most critical issue.
    public var overallStatus: QuotaStatus {
        quotas.map(\.status).max() ?? .healthy
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
