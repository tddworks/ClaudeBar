import Foundation
import Mockable

/// Resolves account identity from external sources (e.g., config files).
@Mockable
public protocol AccountInfoResolving: Sendable {
    func resolve() -> AccountInfo?
}

/// A no-op resolver that always returns `nil`. Useful as a default in tests.
public struct NoOpAccountInfoResolver: AccountInfoResolving {
    public init() {}
    public func resolve() -> AccountInfo? { nil }
}

/// Value object representing account identity information for an AI provider.
/// Encapsulates email, organization, and login method with derived display logic.
public struct AccountInfo: Sendable, Equatable {
    public let email: String?
    public let organization: String?
    public let loginMethod: String?

    /// How the account pays, verbatim from the provider's own config
    /// (Claude's `~/.claude.json` reports `apple_subscription`,
    /// `stripe_subscription`, and so on). Nil when the source does not say.
    public let billingType: String?

    public init(
        email: String? = nil,
        organization: String? = nil,
        loginMethod: String? = nil,
        billingType: String? = nil
    ) {
        self.email = email
        self.organization = organization
        self.loginMethod = loginMethod
        self.billingType = billingType
    }

    /// Whether the account pays through a subscription rather than per-token
    /// API billing.
    ///
    /// Worth knowing because a CLI can misreport it: a Max plan billed through
    /// Apple renders the API-billing cost panel when the CLI cannot read its
    /// subscription credentials, and only the config file still knows better
    /// (#271). The suffix match covers every `*_subscription` form Anthropic
    /// uses without pinning this to the two seen so far.
    public var isSubscriptionBilled: Bool {
        billingType?.hasSuffix("_subscription") == true
    }

    /// The best available name for display: email first, then organization.
    public var displayName: String? {
        email ?? organization
    }

    /// Whether this account info has no useful data.
    public var isEmpty: Bool {
        email == nil && organization == nil
    }

    /// The uppercased first character of the display name, for avatar circles.
    public var initialLetter: String? {
        displayName?.first.map { String($0).uppercased() }
    }
}
