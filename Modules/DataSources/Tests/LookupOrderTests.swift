import DataSources
import Foundation
import Testing

/// *KEY LOOKUP ORDER* — where a data source looks for its key, in order, as
/// the person would recognise it. Never a value.
@Suite
struct LookupOrderTests {
    private func lookup(_ json: String) throws -> CredentialLookup {
        try JSONDecoder().decode(CredentialLookup.self, from: Data(json.utf8))
    }

    @Test
    func `each place is named the way a person would find it`() throws {
        let order = try lookup("""
        { "firstOf": [
            { "jsonFile": { "path": "~/.claude/.credentials.json", "token": "$.claudeAiOauth.accessToken" } },
            { "keychain": { "service": "Claude Code-credentials", "token": "$.claudeAiOauth.accessToken" } },
            { "environment": "CLAUDE_CODE_OAUTH_TOKEN" }
          ],
          "refresh": { "oauth2": { "tokenURL": "https://example.com/token", "clientId": "x",
                                   "hint": "Run `claude` in terminal to log in again." } } }
        """)

        #expect(order.lookupOrder == [
            "~/.claude/.credentials.json",
            "Keychain “Claude Code-credentials”",
            "$CLAUDE_CODE_OAUTH_TOKEN",
        ])
        #expect(order.hint == "Run `claude` in terminal to log in again.")
    }

    @Test
    func `a single place is one step with no hint`() throws {
        let order = try lookup(#"{ "environment": "DEEPSEEK_API_KEY" }"#)

        #expect(order.lookupOrder == ["$DEEPSEEK_API_KEY"])
        #expect(order.hint == nil)
    }

    @Test
    func `a definition can add a note for its data source`() throws {
        let source = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "note": "Needs file credentials.",
          "fetch": { "http": { "url": "https://example.com" } }, "mapping": { "json": { "quotas": [] } } }
        """.utf8))

        #expect(source.note == "Needs file credentials.")
    }
}
