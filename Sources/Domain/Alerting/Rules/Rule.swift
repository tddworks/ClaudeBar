import Foundation
import Quotas

/// *Rules* — the person's own condition on a quota status and their own action:
/// *when my quota drops below 35%, POST to this URL*. One of Alerting's
/// destinations, beside `QuotaAlerts` and the Notify! publication, kept in
/// `~/.claudebar/rules.json` and driven by `QuotaMonitor.onRefreshed`
/// ([design](docs/features/alerting/rules/design.md), CANONICAL §5).
///
/// A rule is data: a condition, an action, a scope and a throttle. The rule for
/// when it says something is `RuleEngine`'s; the rule for what a rule *is* is
/// here, and adding a condition, an action, a scope or a throttle is a case.
public struct Rule: Sendable, Equatable, Identifiable, Codable {
    /// WHEN it says something.
    public enum Condition: Sendable, Equatable, Codable {
        /// The login's worst quota fell below a whole percent, the percent the
        /// person sees.
        case below(percent: Int)
        /// The login's worst quota is critical or worse, under the policy.
        case critical
        /// The login's worst quota is empty.
        case depleted
    }

    /// WHAT it does.
    public enum Action: Sendable, Equatable, Codable {
        /// POST a body to the URL the rule holds. The URL is a secret and lives
        /// in the vault, never here.
        case webhook(channel: WebhookChannel)
    }

    /// WHICH logins it judges.
    public enum Scope: Sendable, Equatable, Codable {
        case everyLogin
        /// One product, by the id its logins name.
        case provider(String)
    }

    /// HOW OFTEN it says something.
    public enum Throttle: Sendable, Equatable, Codable {
        /// Once when the login meets the condition, and again only after it
        /// climbs back out.
        case onceUntilItClimbsBack
    }

    public let id: String
    /// A rule turned off does nothing and keeps its place.
    public var isOn: Bool
    public var condition: Condition
    public var action: Action
    public var scope: Scope
    public var throttle: Throttle

    public init(
        id: String = UUID().uuidString,
        isOn: Bool = true,
        condition: Condition,
        action: Action,
        scope: Scope = .everyLogin,
        throttle: Throttle = .onceUntilItClimbsBack
    ) {
        self.id = id
        self.isOn = isOn
        self.condition = condition
        self.action = action
        self.scope = scope
        self.throttle = throttle
    }
}

extension Rule.Scope {
    /// Whether this scope judges a login of the given product.
    public func covers(providerId: String) -> Bool {
        switch self {
        case .everyLogin: true
        case .provider(let id): id == providerId
        }
    }
}

extension Rule.Condition {
    /// Whether the condition holds for what a refresh read.
    public func isMet(by reading: RuleReading) -> Bool {
        switch self {
        case .below(let percent):
            // The whole percent the person sees: below 35 holds while the
            // reading is 34 or less and stops at 35, so a login hovering at the
            // line is not told again and again.
            reading.percentLeft.map { $0 < percent } ?? false
        case .critical:
            reading.status >= .critical
        case .depleted:
            reading.status == .depleted
        }
    }
}