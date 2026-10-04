import Foundation
import Quotas

/// Settings repository extension for multi-account provider configuration.
///
/// Stores account definitions per provider in the settings JSON.
/// Settings key pattern: `providers.{providerId}.accounts` (array of account configs).
///
/// Each account config contains:
/// - `accountId`: Unique identifier within the provider
/// - `label`: Human-readable name
/// - `email`: Optional email
/// - `organization`: Optional organization
/// - `probeConfig`: Provider-specific probe configuration (e.g., CLI profile, API token env var)
///
/// Note: @Mockable is intentionally omitted here. The macro cannot generate stubs
/// for inherited protocol requirements (Mockable#128). When tests need a mock,
/// use the aggregate-protocol pattern recommended by the Mockable maintainer.
public protocol MultiAccountSettingsRepository: ProviderSettingsRepository {
    /// Gets all configured accounts for a provider.
    /// Returns an empty array for single-account providers (backward compatible).
    func accounts(forProvider id: String) -> [ProviderAccountConfig]

    /// Adds an account configuration for a provider.
    func addAccount(_ config: ProviderAccountConfig, forProvider id: String)

    /// Removes an account configuration by account ID.
    func removeAccount(accountId: String, forProvider id: String)

    /// Updates an existing account configuration.
    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String)

    /// The name the person gave the default login — added logins keep
    /// theirs in `ProviderAccountConfig.label`.
    func defaultAccountLabel(forProvider id: String) -> String?

    /// Saves the default login's name; `nil` forgets it.
    func setDefaultAccountLabel(_ label: String?, forProvider id: String)

    /// The order the person put the logins in, by account id (`default` for
    /// the default login). Empty until they move one.
    func accountOrder(forProvider id: String) -> [String]

    func setAccountOrder(_ accountIds: [String], forProvider id: String)
}

/// Configuration for a single account within a provider.
/// Serializable to/from the settings JSON.
public struct ProviderAccountConfig: Sendable, Equatable, Codable {
    /// Unique identifier within the provider
    public let accountId: String

    /// Human-readable label
    public let label: String

    /// Optional email
    public let email: String?

    /// Optional organization
    public let organization: String?

    /// Provider-specific probe configuration.
    /// For CLI-based providers: could be a profile name or config path.
    /// For API-based providers: could be an env var name for the token.
    /// Stored as a dictionary for flexibility across provider types.
    public let probeConfig: [String: String]

    /// How the login was added — which decides what *Remove* may delete.
    /// `nil` for logins saved before it was recorded: treated as chosen.
    public let madeBy: AccountOrigin?

    public init(
        accountId: String,
        label: String,
        email: String? = nil,
        organization: String? = nil,
        probeConfig: [String: String] = [:],
        madeBy: AccountOrigin? = nil
    ) {
        self.accountId = accountId
        self.label = label
        self.email = email
        self.organization = organization
        self.probeConfig = probeConfig
        self.madeBy = madeBy
    }

    /// Converts to a ProviderAccount domain model
    /// The same login under another name — who it is and its values stay.
    public func named(_ label: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: accountId, label: label, email: email, organization: organization,
                              probeConfig: probeConfig, madeBy: madeBy)
    }

    /// The same login, recorded as added that way.
    public func made(by origin: AccountOrigin) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: accountId, label: label, email: email, organization: organization,
                              probeConfig: probeConfig, madeBy: origin)
    }

    public func toProviderAccount(providerId: String) -> ProviderAccount {
        ProviderAccount(
            accountId: accountId,
            providerId: providerId,
            label: label,
            email: email,
            organization: organization
        )
    }
}

/// How a login was added: *Choose Signed-in Folder*, *Sign in with browser*
/// (into a folder ClaudeBar made), or the account's form.
public enum AccountOrigin: String, Sendable, Equatable, Codable {
    case folder, signIn, form
}
