import Foundation
import Quotas

/// After each refresh, which of the person's rules a login met — once, and
/// again only after the login climbs back out of the condition
/// ([design](docs/features/alerting/rules/design.md), CANONICAL §5).
///
/// It follows refreshes through `QuotaMonitor.onRefreshed`, so the Monitor
/// knows nothing of it. A paused login is never refreshed, so it is never
/// reviewed here.
@MainActor
public final class RuleEngine {
    private let set: RuleSet
    private let sender: any WebhookSending

    /// Per rule, the logins currently meeting its condition. In memory: after a
    /// relaunch a login still below is told once more.
    private var inCondition: [String: Set<String>] = [:]

    /// What each rule last looked like. A rule whose condition, scope, action or
    /// switch changed forgets who was in, so a changed rule starts fresh.
    private var seen: [String: Rule] = [:]

    /// An engine over the person's rules, sending through `sender`.
    public init(set: RuleSet, sender: any WebhookSending) {
        self.set = set
        self.sender = sender
    }

    /// After a refresh: sends for each of the person's rules this login just met.
    /// `login.usage` is what the person sees — hidden quotas already left out.
    public func review(_ login: RuleLogin, under policy: StatusPolicy) async {
        guard let reading = RuleReading.worst(of: login, under: policy) else { return }

        for rule in set.rules {
            if seen[rule.id] != rule {
                inCondition[rule.id] = []
                seen[rule.id] = rule
            }
            guard rule.isOn, rule.scope.covers(providerId: login.providerId) else { continue }

            // Recorded before the POST is awaited: `review` is re-entrant at an
            // await, and two logins refreshed at once each run it. A
            // read-modify-write that straddled the await would drop the login
            // that wrote first and tell it again on the next refresh.
            if rule.condition.isMet(by: reading) {
                if inCondition[rule.id, default: []].insert(login.id).inserted {
                    await deliver(rule, reading)
                }
            } else {
                inCondition[rule.id]?.remove(login.id)
            }
        }

        // Forget rules the person removed, so a long-lived engine keeps no
        // memory of a rule that no longer exists.
        let live = Set(set.rules.map(\.id))
        inCondition = inCondition.filter { live.contains($0.key) }
        seen = seen.filter { live.contains($0.key) }
    }

    /// *Try it*: sends whatever the condition says, and however many times it is
    /// pressed, so the pane can prove a URL works before trusting it.
    @discardableResult
    public func tryIt(_ rule: Rule, for login: RuleLogin, under policy: StatusPolicy) async -> RuleOutcome {
        guard let reading = RuleReading.worst(of: login, under: policy) else { return .nothingToSend }
        return await deliver(rule, reading)
    }

    /// One attempt, never a retry. The sender logs the route and the status —
    /// never the URL; a failure leaves the rule "in", so the same crossing is
    /// not tried forever.
    @discardableResult
    private func deliver(_ rule: Rule, _ reading: RuleReading) async -> RuleOutcome {
        do {
            try await sender.send(WebhookBody(rule: rule, reading: reading), forRule: rule.id)
            return .sent
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}