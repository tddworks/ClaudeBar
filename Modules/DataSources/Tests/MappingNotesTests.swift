import DataSources
import Foundation
import Quotas
import Testing

/// A JSON mapping can show a count the answer sends that is not a limit —
/// nothing is left of it and nothing refills — as a note beside the quotas:
/// "Usage limit resets · 1 · available".
@Suite
struct MappingNotesTests {
    private func usage(_ body: String) throws -> UsageSnapshot {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "fetch": { "http": { "url": "https://example.com" } }, "mapping": { "json": {
          "quotas": [{ "kind": "session", "at": "$.primary", "usedPercent": "used" }],
          "notes": [{ "label": "Usage limit resets", "value": ["$.resets.count", "$.legacy_count"], "unit": "available" }]
        } } }
        """.utf8))
        return try DataSources.make(definition, providerId: "codex").read(Response(status: 200, body: Data(body.utf8)))
    }

    @Test
    func `should show a count the answer sends as a note with its unit`() throws {
        let usage = try usage(#"{"primary":{"used":10},"resets":{"count":2}}"#)

        #expect(usage.extensionMetrics == [ExtensionMetric(label: "Usage limit resets", value: "2", unit: "available")])
        #expect(usage.quotas.count == 1)
    }

    @Test
    func `should show a count of none rather than hide it`() throws {
        let usage = try usage(#"{"primary":{"used":10},"resets":{"count":0}}"#)

        #expect(usage.extensionMetrics?.first?.value == "0")
    }

    @Test
    func `should read the first place that answers`() throws {
        let usage = try usage(#"{"primary":{"used":10},"resets":null,"legacy_count":3}"#)

        #expect(usage.extensionMetrics?.first?.value == "3")
    }

    @Test(arguments: [#"{"primary":{"used":10}}"#, #"{"primary":{"used":10},"resets":{"count":null}}"#, #"{"primary":{"used":10},"resets":{"count":true}}"#])
    func `should show no note when the answer doesn't send the count`(_ body: String) throws {
        let usage = try usage(body)

        #expect(usage.extensionMetrics == nil)
    }

    private func notes(_ rules: String, _ body: String) throws -> [ExtensionMetric]? {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "fetch": { "http": { "url": "https://example.com" } }, "mapping": { "json": {
          "quotas": [], "notes": \(rules)
        } } }
        """.utf8))
        return try DataSources.make(definition, providerId: "codex").read(Response(status: 200, body: Data(body.utf8))).extensionMetrics
    }

    /// A balance with no limit, as Codex sends it: a string with ten decimals.
    private let balance = #"[{ "label": "Credits", "when": { "path": "$.credits.has_credits", "equals": true }, "value": "$.credits.balance", "unit": "credits", "round": 0 }]"#

    @Test
    func `should show a balance as a whole number with its thousands grouped`() throws {
        let notes = try notes(balance, #"{"credits":{"has_credits":true,"balance":"62500.0000000000"}}"#)

        #expect(notes == [ExtensionMetric(label: "Credits", value: "62,500", unit: "credits")])
    }

    @Test(arguments: [("1234.5", 1, "1,234.5"), ("0.0000000000", 0, "0"), ("-12.6", 0, "-13"), ("7", 2, "7")])
    func `should show a number to the places the definition keeps, no more`(_ sent: String, _ places: Int, _ shown: String) throws {
        let notes = try notes(#"[{ "label": "Credits", "value": "$.balance", "round": \#(places) }]"#, #"{"balance":"\#(sent)"}"#)

        #expect(notes?.first?.value == shown)
    }

    @Test
    func `should read the next place when a number is wanted and the first sends words`() throws {
        let notes = try notes(#"[{ "label": "Credits", "value": ["$header.x-balance", "$.balance", "$.legacy"], "round": 0 }]"#, #"{"balance":"n/a","legacy":3.2}"#)

        #expect(notes?.first?.value == "3")
    }

    @Test
    func `should show no note while its condition doesn't hold`() throws {
        let notes = try notes(balance, #"{"credits":{"has_credits":false,"balance":"0"}}"#)

        #expect(notes == nil)
    }

    @Test
    func `should show the words the definition gives while its condition holds`() throws {
        let rules = #"[{ "label": "Credits", "when": { "path": "$.unlimited", "equals": true }, "text": "Unlimited" }]"#

        #expect(try notes(rules, #"{"unlimited":true}"#) == [ExtensionMetric(label: "Credits", value: "Unlimited", unit: "")])
        #expect(try notes(rules, #"{"unlimited":false}"#) == nil)
    }

    @Test
    func `should show one note per label, the first that answers`() throws {
        let rules = #"""
        [{ "label": "Credits", "when": { "path": "$.credits.unlimited", "equals": true }, "text": "Unlimited" },
         { "label": "Credits", "when": { "path": "$.credits.has_credits", "equals": true }, "value": "$.credits.balance", "unit": "credits", "round": 0 }]
        """#

        #expect(try notes(rules, #"{"credits":{"has_credits":true,"unlimited":true,"balance":"10"}}"#) == [ExtensionMetric(label: "Credits", value: "Unlimited", unit: "")])
        #expect(try notes(rules, #"{"credits":{"has_credits":true,"unlimited":false,"balance":"10"}}"#) == [ExtensionMetric(label: "Credits", value: "10", unit: "credits")])
    }
}
