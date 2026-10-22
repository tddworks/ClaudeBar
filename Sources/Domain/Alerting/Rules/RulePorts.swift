import Foundation
import Mockable

/// Where the person's rules are kept. A destination's own repository, beside
/// `NotifySettingsRepository` and `HookSettingsRepository` — never a provider
/// setting. The rules go to `~/.claudebar/rules.json`; the webhook URL is a
/// secret and goes to the vault, never to that file (CANONICAL §5).
@Mockable
public protocol RuleRepository: Sendable {
    /// The rules as saved, in the order they were added.
    func rules() -> [Rule]
    /// Replaces the saved rules.
    func setRules(_ rules: [Rule])

    /// The webhook URL one rule holds, nil until it has one. A secret.
    func webhookURL(forRule ruleId: String) -> String?
    /// Stores a URL, or clears it when empty or nil.
    func setWebhookURL(_ url: String?, forRule ruleId: String)
}

/// Who carries a rule's action out. One implementation, in Infrastructure,
/// which is the only place a `URLRequest` is built; Domain knows nothing about
/// URLs.
@Mockable
public protocol WebhookSending: Sendable {
    /// Sends one body for the rule that produced it. The URL is the sender's to
    /// find — Domain never holds it.
    func send(_ body: WebhookBody, forRule ruleId: String) async throws
}

/// What happened when a rule was tried, in words Settings can print. A failure
/// carries the sender's own sentence, which never quotes the URL.
public enum RuleOutcome: Sendable, Equatable {
    case sent
    case nothingToSend
    case failed(String)

    /// What the person reads after *Try it*.
    public var message: String {
        switch self {
        case .sent: "Sent."
        case .nothingToSend: "Nothing to send — that login reports no quota yet."
        case .failed(let reason): reason
        }
    }
}