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
        let mapper = ScriptMapper(file: "s.js", source: script, values: values, engine: QuickJSEngine(),
                                  zone: Zones.seoul, now: { Date() })
        return try #require(try mapper.read(Response(text: "{}"), facts: MappingFacts(), providerId: "acme").quotas.first)
    }

    @Test func `should hand a script the settings the person filled in`() throws {
        let quota = try read(["limit": "40", "manual": "12"])
        #expect(quota.percentRemaining == 40)
        #expect(quota.resetText == "manual 12")
    }

    @Test func `should leave out a setting the person left blank`() throws {
        let quota = try read(["limit": "{{setting.limit}}", "manual": "{{setting.manual}}"])
        #expect(quota.percentRemaining == 7)
        #expect(quota.resetText == "no manual")
    }

    @Test func `should keep a script's setting templates when its definition is saved and read back`() throws {
        let mapping = try JSONDecoder().decode(ScriptMapping.self, from: Data(#"{"file":"s.js","values":{"limit":"{{setting.limit}}"}}"#.utf8))
        #expect(mapping.values == ["limit": "{{setting.limit}}"])
        #expect(try JSONDecoder().decode(ScriptMapping.self, from: JSONEncoder().encode(mapping)) == mapping)
    }
}
