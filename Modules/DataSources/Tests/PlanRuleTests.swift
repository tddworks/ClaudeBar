import Foundation
import Quotas
import Testing
@testable import DataSources

/// The plan badge a JSON mapping names — one rule, or a list where the first
/// rule whose `when` holds and that answers wins: a plan two fields tell
/// apart, such as a tier only a second field names.
@Suite
struct PlanRuleTests {
    private func mapping(_ json: String) throws -> JSONMapping {
        guard case .json(let mapping) = try JSONDecoder().decode(Mapping.self, from: Data(json.utf8)) else {
            throw CocoaError(.coderInvalidValue)
        }
        return mapping
    }

    private func plan(_ mapping: JSONMapping, credential: [String: String]) throws -> AccountTier? {
        try JSONMapper(mapping: mapping, now: { Date() })
            .read(Response(text: "{}"), facts: MappingFacts(credential: credential), providerId: "acme")
            .accountTier
    }

    private static let tiered = #"""
    {"json":{"quotas":[],"plan":[
      {"when":{"path":"$credential.tier","equals":"top"},"path":"$credential.plan","plans":{"max":"ULTRA"}},
      {"path":"$credential.plan","plans":{"max":"claudeMax","pro":"claudePro"}}
    ]}}
    """#

    @Test
    func `should show the plan a second field sets apart when its condition holds`() throws {
        let mapping = try mapping(Self.tiered)

        #expect(try plan(mapping, credential: ["plan": "max", "tier": "top"]) == .custom("ULTRA"))
    }

    @Test
    func `should show the next rule's plan when the condition does not hold`() throws {
        let mapping = try mapping(Self.tiered)

        #expect(try plan(mapping, credential: ["plan": "max", "tier": "middle"]) == .claudeMax)
        #expect(try plan(mapping, credential: ["plan": "max"]) == .claudeMax)
    }

    @Test
    func `should show no plan when no rule answers`() throws {
        let mapping = try mapping(Self.tiered)

        #expect(try plan(mapping, credential: [:]) == nil)
    }

    @Test
    func `should still read a plan written as one rule`() throws {
        let one = try mapping(#"{"json":{"quotas":[],"plan":{"path":"$credential.plan","plans":{"max":"claudeMax"}}}}"#)
        let bare = try mapping(#"{"json":{"quotas":[],"plan":"$credential.plan"}}"#)

        #expect(try plan(one, credential: ["plan": "max"]) == .claudeMax)
        #expect(try plan(bare, credential: ["plan": "plus"]) == .custom("PLUS"))
    }
}
