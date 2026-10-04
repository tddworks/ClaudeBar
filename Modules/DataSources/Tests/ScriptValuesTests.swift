import Foundation
import Quotas
import Testing
@testable import DataSources

/// A script reads the settings its definition hands it as `context.values`;
/// a setting left blank never filled its template, so it isn't there.
@Suite
struct ScriptValuesTests {
    private let script = """
    function read(response, context) {
        const limit = context.values.limit;
        return {quotas: [{type: 'time', name: 'Monthly', percentRemaining: limit ? Number(limit) : 7,
                          resetText: context.values.manual === undefined ? 'no manual' : 'manual ' + context.values.manual}]};
    }
    """

    private func read(_ values: [String: String]) throws -> UsageQuota {
        let mapper = ScriptMapper(file: "s.js", source: script, values: values, now: { Date() })
        return try #require(try mapper.read(Response(text: "{}"), facts: MappingFacts(), providerId: "acme").quotas.first)
    }

    @Test func `filled values reach the script`() throws {
        let quota = try read(["limit": "40", "manual": "12"])
        #expect(quota.percentRemaining == 40)
        #expect(quota.resetText == "manual 12")
    }

    @Test func `a value still holding its template is left out`() throws {
        let quota = try read(["limit": "{{setting.limit}}", "manual": "{{setting.manual}}"])
        #expect(quota.percentRemaining == 7)
        #expect(quota.resetText == "no manual")
    }

    @Test func `values survive a round trip`() throws {
        let mapping = try JSONDecoder().decode(ScriptMapping.self, from: Data(#"{"file":"s.js","values":{"limit":"{{setting.limit}}"}}"#.utf8))
        #expect(mapping.values == ["limit": "{{setting.limit}}"])
        #expect(try JSONDecoder().decode(ScriptMapping.self, from: JSONEncoder().encode(mapping)) == mapping)
    }
}
