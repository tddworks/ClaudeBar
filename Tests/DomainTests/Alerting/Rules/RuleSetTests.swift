import Foundation
import Testing
@testable import Domain

/// The person's rules: added, changed, turned off and forgotten — and kept.
@MainActor
@Suite
struct RuleSetTests {
    private final class Kept: RuleRepository, @unchecked Sendable {
        var stored: [Rule]
        var urls: [String: String] = [:]
        var cleared: [String] = []
        init(_ rules: [Rule] = []) { self.stored = rules }
        func rules() -> [Rule] { stored }
        func setRules(_ rules: [Rule]) { stored = rules }
        func webhookURL(forRule ruleId: String) -> String? { urls[ruleId] }
        func setWebhookURL(_ url: String?, forRule ruleId: String) {
            if let url, !url.isEmpty { urls[ruleId] = url } else { urls[ruleId] = nil; cleared.append(ruleId) }
        }
    }

    private func aRule() -> Rule {
        Rule(condition: .below(percent: 35), action: .webhook(channel: .slack))
    }

    @Test func `should keep a rule and its webhook URL where they belong`() {
        let kept = Kept()
        let rules = RuleSet(repository: kept)

        let rule = aRule()
        rules.add(rule, webhookURL: "https://hooks.example.test/services/T/B")

        #expect(rules.rules == [rule])
        #expect(kept.stored == [rule])
        // The URL is the vault's, never the rule's.
        #expect(kept.urls[rule.id] == "https://hooks.example.test/services/T/B")
        #expect(rules.webhookURL(for: rule) == "https://hooks.example.test/services/T/B")
        #expect(rules.hasWebhookURL(for: rule))
    }

    @Test func `should read the saved rules at launch`() {
        let rule = aRule()
        #expect(RuleSet(repository: Kept([rule])).rules == [rule])
    }

    @Test func `should replace a rule in place and keep the others`() {
        let kept = Kept()
        let rules = RuleSet(repository: kept)
        let first = aRule()
        let second = Rule(condition: .depleted, action: .webhook(channel: .json))
        rules.add(first, webhookURL: "https://example.test/a")
        rules.add(second, webhookURL: "https://example.test/b")

        var changed = first
        changed.condition = .below(percent: 50)
        rules.update(changed, webhookURL: "https://example.test/a2")

        #expect(rules.rules == [changed, second])
        #expect(kept.stored == [changed, second])
        #expect(kept.urls[first.id] == "https://example.test/a2")
    }

    @Test func `should leave a rule's URL alone when an edit gives none`() {
        let kept = Kept()
        let rules = RuleSet(repository: kept)
        let rule = aRule()
        rules.add(rule, webhookURL: "https://example.test/a")

        var changed = rule
        changed.condition = .critical
        rules.update(changed)

        #expect(rules.webhookURL(for: rule) == "https://example.test/a")
    }

    @Test func `should turn a rule off and on without forgetting it`() {
        let kept = Kept()
        let rules = RuleSet(repository: kept)
        let rule = aRule()
        rules.add(rule, webhookURL: "https://example.test/a")

        rules.setOn(false, for: rule)

        #expect(rules.rules.first?.isOn == false)
        #expect(rules.rules.first?.id == rule.id)
        #expect(rules.webhookURL(for: rule) == "https://example.test/a")
    }

    @Test func `should forget a rule and its URL when the person removes it`() {
        let kept = Kept()
        let rules = RuleSet(repository: kept)
        let rule = aRule()
        rules.add(rule, webhookURL: "https://example.test/a")

        rules.remove(rule)

        #expect(rules.rules.isEmpty)
        #expect(kept.urls[rule.id] == nil)
        #expect(kept.cleared.contains(rule.id))
    }

    @Test func `should not claim a URL a rule does not have`() {
        let rules = RuleSet(repository: Kept())
        let rule = aRule()

        #expect(rules.webhookURL(for: rule) == nil)
        #expect(!rules.hasWebhookURL(for: rule))
    }
}