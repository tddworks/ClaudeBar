import Foundation
import Observation

/// The person's rules — *when my quota drops below 35%, POST to this URL* —
/// saved in `~/.claudebar/rules.json` and read by `RuleEngine` after every
/// refresh ([design](docs/features/alerting/rules/design.md)).
///
/// A destination's own, beside `QuotaAlerts` and the Notify! publication:
/// adding a rule never touches a provider's settings, and a rule turned off
/// keeps its place.
@MainActor
@Observable
public final class RuleSet {
    /// The person's rules, in the order they were added.
    public private(set) var rules: [Rule]

    @ObservationIgnored private let repository: any RuleRepository

    /// The person's rules, read from `repository` at launch.
    public init(repository: any RuleRepository) {
        self.repository = repository
        self.rules = repository.rules()
    }

    /// Adds a rule, and its webhook URL when one was given. The URL is a secret
    /// and goes to the vault, never to the rules file.
    public func add(_ rule: Rule, webhookURL: String? = nil) {
        keep(rules + [rule])
        if let webhookURL { repository.setWebhookURL(webhookURL, forRule: rule.id) }
    }

    /// Replaces a rule in place, by id. The URL is left alone when none is
    /// given; an empty one clears it.
    public func update(_ rule: Rule, webhookURL: String? = nil) {
        guard rules.contains(where: { $0.id == rule.id }) else { return }
        keep(rules.map { $0.id == rule.id ? rule : $0 })
        if let webhookURL { repository.setWebhookURL(webhookURL, forRule: rule.id) }
    }

    /// Forgets a rule and its URL. Turning a rule off is not this.
    public func remove(_ rule: Rule) {
        keep(rules.filter { $0.id != rule.id })
        repository.setWebhookURL(nil, forRule: rule.id)
    }

    /// *Turn on* / *Turn off* — the rule keeps everything and does nothing while
    /// it is off.
    public func setOn(_ on: Bool, for rule: Rule) {
        var updated = rule
        updated.isOn = on
        update(updated)
    }

    /// The webhook URL a rule holds, nil until it has one.
    public func webhookURL(for rule: Rule) -> String? {
        repository.webhookURL(forRule: rule.id)
    }

    /// Whether a rule can send at all — it has a URL.
    public func hasWebhookURL(for rule: Rule) -> Bool {
        !(webhookURL(for: rule) ?? "").isEmpty
    }

    /// The one place the list is replaced, so memory and the file move together.
    private func keep(_ list: [Rule]) {
        rules = list
        repository.setRules(list)
    }
}