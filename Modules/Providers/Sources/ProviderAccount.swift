import Foundation
import Quotas

/// Represents a named account within an AI provider.
///
/// A provider can have multiple accounts (e.g., personal Claude Pro + work Claude Max).
/// Each account has its own identity, probe configuration, and usage snapshot.
///
/// The compound ID format is `{providerId}.{accountId}` (e.g., "claude.personal",
/// "claude.work"). For single-account providers, the account ID is "default" and
/// the compound ID equals the provider ID (backward compatible).
public struct ProviderAccount: Sendable, Equatable, Identifiable {
    /// Unique identifier for this account within its provider (e.g., "personal", "work")
    public let accountId: String

    /// The provider type this account belongs to (e.g., "claude", "codex")
    public let providerId: String

    /// Human-readable label for this account (e.g., "Personal", "Work - Acme Corp")
    public let label: String

    /// The email associated with this account (if known)
    public let email: String?

    /// The organization associated with this account (if known)
    public let organization: String?

    // MARK: - Identifiable

    /// Compound ID: `{providerId}.{accountId}` for multi-account,
    /// or just `{providerId}` for the default account.
    public var id: String {
        if accountId == ProviderAccount.defaultAccountId {
            return providerId
        }
        return "\(providerId).\(accountId)"
    }

    // MARK: - Constants

    /// The account ID used for single-account providers (backward compatible)
    public static let defaultAccountId = "default"

    // MARK: - Initialization

    /// Creates a provider account.
    /// - Parameters:
    ///   - accountId: Unique identifier within the provider (default: "default")
    ///   - providerId: The provider type (e.g., "claude")
    ///   - label: Human-readable label
    ///   - email: Optional email for this account
    ///   - organization: Optional organization name
    public init(
        accountId: String = ProviderAccount.defaultAccountId,
        providerId: String,
        label: String,
        email: String? = nil,
        organization: String? = nil
    ) {
        self.accountId = accountId
        self.providerId = providerId
        self.label = label
        self.email = email
        self.organization = organization
    }

    // MARK: - Display

    /// Best available display name: label first, then email, then account ID
    public var displayName: String {
        if !label.isEmpty {
            return label
        }
        return email ?? accountId
    }

    /// Whether this is the default (single) account
    public var isDefault: Bool {
        accountId == ProviderAccount.defaultAccountId
    }

    /// The uppercased first character of the display name, for avatar circles.
    public var initialLetter: String {
        String(displayName.prefix(1)).uppercased()
    }
}
