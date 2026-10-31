import Foundation

/// Represents the account tier for any AI provider.
/// Supports both well-known tiers (Claude Max/Pro/API) and custom tiers from other providers.
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md): Becomes `Plan`: a name and a badge. The Claude cases are vendor words that
///   don't belong in the kernel; which plans can send guest passes is a fact
///   the definition states (`"guestPasses": { "plans": [...] }`).
public enum AccountTier: Sendable, Equatable, Hashable {
    /// Claude Max subscription with session/weekly quotas + optional extra usage cost tracking
    case claudeMax
    /// Claude Pro subscription with session/weekly quotas + optional extra usage cost tracking
    case claudePro
    /// Claude API account with pay-per-use pricing (cost tracking only)
    case claudeApi
    /// Custom tier for any provider (badge text, e.g., "PRO", "ULTRA")
    case custom(String)

    // MARK: - Display Properties

    /// Display name for the account tier
    public var displayName: String {
        switch self {
        case .claudeMax: return "Claude Max"
        case .claudePro: return "Claude Pro"
        case .claudeApi: return "API Usage"
        case .custom(let badge): return badge
        }
    }

    /// Short badge text for compact display
    public var badgeText: String {
        switch self {
        case .claudeMax: return "MAX"
        case .claudePro: return "PRO"
        case .claudeApi: return "API"
        case .custom(let badge): return badge
        }
    }
}

// MARK: - Legacy Type Alias

@available(*, deprecated, renamed: "AccountTier")
public typealias ClaudeAccountType = AccountTier
