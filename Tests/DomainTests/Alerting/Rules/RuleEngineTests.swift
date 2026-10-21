import Foundation
import Testing
import Mockable
@testable import Domain

/// *Rules* ([design](docs/features/alerting/rules/design.md)): the person's own
/// condition and their own webhook, told once when a login meets it and again
/// only after it climbs back out.
@MainActor
@Suite
struct RuleEngineTests {
    // MARK: - Doubles

    private final class Kept: RuleRepository, @unchecked Sendable {
        var stored: [Rule]
        var urls: [String: String] = [:]
        init(_ rules: [Rule] = []) { self.stored = rules }
        func rules() -> [Rule] { stored }
        func setRules(_ rules: [Rule]) { stored = rules }
        func webhookURL(forRule ruleId: String) -> String? { urls[ruleId] }
        func setWebhookURL(_ url: String?, forRule ruleId: String) {
            urls[ruleId] = (url?.isEmpty == true) ? nil : url
        }
    }

    private struct Refused: Error, LocalizedError {
        var errorDescription: String? { "The server said no." }
    }

    private final class Sent: WebhookSending, @unchecked Sendable {
        var bodies: [WebhookBody] = []
        var attempts = 0
        var refusal: (any Error)?
        func send(_ body: WebhookBody, forRule ruleId: String) async throws {
            attempts += 1
            if let refusal { throw refusal }
            bodies.append(body)
        }
    }

    /// A sender that runs a closure mid-send, so a test can re-enter `review`
    /// at the await the way a second login's refresh does.
    private final class Reentrant: WebhookSending, @unchecked Sendable {
        var bodies: [WebhookBody] = []
        var during: (@MainActor () async -> Void)?
        func send(_ body: WebhookBody, forRule ruleId: String) async throws {
            bodies.append(body)
            if let during {
                self.during = nil
                await during()
            }
        }
    }

    private let sent = Sent()

    /// A rule set holding exactly `list`, each with a URL.
    private func set(_ list: [Rule], url: String? = "https://example.test/hook") -> RuleSet {
        let kept = Kept()
        let set = RuleSet(repository: kept)
        for rule in list { set.add(rule, webhookURL: url) }
        return set
    }

    private func engine(_ list: [Rule]) -> RuleEngine {
        RuleEngine(set: set(list), sender: sent)
    }

    private func usage(_ lefts: Left...) -> UsageSnapshot {
        UsageSnapshot(providerId: "claude",
                      quotas: lefts.map { UsageQuota(left: $0, quotaType: .session, providerId: "claude") },
                      capturedAt: Date())
    }

    private func login(_ id: String = "claude", provider: String = "claude", name: String = "Claude", usage: UsageSnapshot?) -> RuleLogin {
        RuleLogin(id: id, providerId: provider, name: name, usage: usage)
    }

    private func below(_ percent: Int) -> Rule {
        Rule(condition: .below(percent: percent), action: .webhook(channel: .slack))
    }

    // MARK: - Once per crossing

    @Test func `should send once when a login falls below the rule's percent`() async {
        let engine = engine([below(35)])

        await engine.review(login(usage: usage(.share(40))), under: .absolute)
        await engine.review(login(usage: usage(.share(34))), under: .absolute)

        #expect(sent.bodies.count == 1)
        #expect(sent.bodies.first?.reading.percentLeft == 34)
    }

    @Test func `should stay quiet while the login stays below`() async {
        let engine = engine([below(35)])

        for percent in [34.0, 30, 31, 12] { await engine.review(login(usage: usage(.share(percent))), under: .absolute) }

        #expect(sent.bodies.count == 1)
    }

    @Test func `should send again after the login climbs back to the percent`() async {
        let engine = engine([below(35)])

        for percent in [34.0, 35, 33] { await engine.review(login(usage: usage(.share(percent))), under: .absolute) }

        #expect(sent.bodies.count == 2)
    }

    @Test func `should not send again when the login climbs back less than a whole point`() async {
        let engine = engine([below(35)])

        for percent in [34.0, 34.9, 34] { await engine.review(login(usage: usage(.share(percent))), under: .absolute) }

        #expect(sent.bodies.count == 1)
    }

    @Test func `should keep each login's crossing its own`() async {
        let engine = engine([below(35)])

        await engine.review(login("claude", name: "Claude · me", usage: usage(.share(30))), under: .absolute)
        await engine.review(login("claude.work", name: "Claude · work", usage: usage(.share(30))), under: .absolute)

        #expect(sent.bodies.map(\.reading.login) == ["Claude · me", "Claude · work"])
    }

    @Test func `should tell each login once when two reviews overlap`() async {
        let reentrant = Reentrant()
        let engine = RuleEngine(set: set([below(35)]), sender: reentrant)
        // The first login's send re-enters `review` for a second login, the way
        // two refreshes running at once interleave at the await.
        reentrant.during = { await engine.review(self.login("b", name: "B", usage: self.usage(.share(10))), under: .absolute) }

        await engine.review(login("a", name: "A", usage: usage(.share(10))), under: .absolute)
        // A later refresh of the second login: it is still below, so it must stay quiet.
        await engine.review(login("b", name: "B", usage: usage(.share(10))), under: .absolute)

        #expect(reentrant.bodies.map(\.reading.login) == ["A", "B"])
    }

    @Test func `should send for a login already below when the rule is added`() async {
        let engine = engine([below(35)])

        await engine.review(login(usage: usage(.share(10))), under: .absolute)

        #expect(sent.bodies.count == 1)
    }

    // MARK: - What it judges

    @Test func `should judge the login's worst quota`() async {
        let engine = engine([below(35)])

        await engine.review(login(usage: usage(.share(80), .share(20))), under: .absolute)

        #expect(sent.bodies.first?.reading.percentLeft == 20)
    }

    @Test func `should never judge a balance without a ceiling by a percent`() async {
        let engine = engine([below(35)])

        await engine.review(login(usage: usage(.money(Money(1), of: nil))), under: .absolute)

        #expect(sent.bodies.isEmpty)
    }

    @Test func `should judge a depleted condition on a balance without a ceiling`() async {
        let engine = engine([Rule(condition: .depleted, action: .webhook(channel: .json))])

        await engine.review(login(usage: usage(.money(Money(0), of: nil))), under: .absolute)

        #expect(sent.bodies.count == 1)
    }

    @Test func `should read a critical condition under the person's policy`() async {
        let engine = engine([Rule(condition: .critical, action: .webhook(channel: .slack))])

        await engine.review(login(usage: usage(.share(45))), under: .absolute)
        await engine.review(login(usage: usage(.share(15))), under: .absolute)

        #expect(sent.bodies.count == 1)
        #expect(sent.bodies.first?.reading.status == .critical)
    }

    @Test func `should send nothing for a login with no usage`() async {
        let engine = engine([below(35)])

        await engine.review(login(usage: nil), under: .absolute)

        #expect(sent.bodies.isEmpty)
    }

    // MARK: - Scope and the switch

    @Test func `should only judge a rule's own provider`() async {
        let rule = Rule(condition: .below(percent: 35), action: .webhook(channel: .slack), scope: .provider("codex"))
        let engine = engine([rule])

        await engine.review(login("claude", provider: "claude", usage: usage(.share(10))), under: .absolute)
        await engine.review(login("codex", provider: "codex", usage: usage(.share(10))), under: .absolute)

        #expect(sent.bodies.count == 1)
        #expect(sent.bodies.first?.reading.providerId == "codex")
    }

    @Test func `should do nothing for a rule that is off`() async {
        let rule = Rule(isOn: false, condition: .below(percent: 35), action: .webhook(channel: .slack))
        let engine = engine([rule])

        await engine.review(login(usage: usage(.share(10))), under: .absolute)

        #expect(sent.bodies.isEmpty)
    }

    // MARK: - A rule that changes

    @Test func `should forget a crossing when the rule's condition changes`() async {
        let kept = Kept()
        let set = RuleSet(repository: kept)
        let rule = below(35)
        set.add(rule, webhookURL: "https://example.test/hook")
        let engine = RuleEngine(set: set, sender: sent)

        await engine.review(login(usage: usage(.share(34))), under: .absolute)
        var changed = rule
        changed.condition = .below(percent: 50)
        set.update(changed)
        await engine.review(login(usage: usage(.share(34))), under: .absolute)

        #expect(sent.bodies.count == 2)
    }

    @Test func `should forget the crossings of a rule the person removes`() async {
        let kept = Kept()
        let set = RuleSet(repository: kept)
        let rule = below(35)
        set.add(rule, webhookURL: "https://example.test/hook")
        let engine = RuleEngine(set: set, sender: sent)

        await engine.review(login(usage: usage(.share(34))), under: .absolute)
        set.remove(rule)
        await engine.review(login(usage: usage(.share(34))), under: .absolute)

        #expect(sent.bodies.count == 1)
    }

    // MARK: - Try it

    @Test func `should try a rule whatever the condition says, again and again`() async {
        let engine = engine([below(35)])

        let outcome = await engine.tryIt(below(35), for: login(usage: usage(.share(90))), under: .absolute)
        _ = await engine.tryIt(below(35), for: login(usage: usage(.share(90))), under: .absolute)

        #expect(outcome == .sent)
        #expect(sent.bodies.count == 2)
    }

    @Test func `should report nothing to send when a tried login has no usage`() async {
        let engine = engine([below(35)])

        let outcome = await engine.tryIt(below(35), for: login(usage: nil), under: .absolute)

        #expect(outcome == .nothingToSend)
        #expect(sent.bodies.isEmpty)
    }

    @Test func `should report a failure and not try again while the login stays below`() async {
        let engine = engine([below(35)])
        sent.refusal = Refused()

        await engine.review(login(usage: usage(.share(34))), under: .absolute)
        await engine.review(login(usage: usage(.share(30))), under: .absolute)

        #expect(sent.attempts == 1)
    }

    @Test func `should report a failure with the sender's sentence`() async {
        let engine = engine([below(35)])
        sent.refusal = Refused()

        let outcome = await engine.tryIt(below(35), for: login(usage: usage(.share(10))), under: .absolute)

        #expect(outcome == .failed("The server said no."))
    }
}