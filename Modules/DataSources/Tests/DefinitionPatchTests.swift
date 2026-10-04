import DataSources
import Foundation
import Testing

/// A definition as data a login can adapt: an RFC 7396 merge patch changes
/// what differs, and a login's values fill `{{account.x}}` — one definition,
/// never a copy per login.
@Suite
struct DefinitionPatchTests {
    private static let rpc = """
    {
      "kind": "rpc",
      "label": "RPC",
      "fetch": { "jsonRpc": { "cli": "codex", "args": ["app-server"], "call": "account/rateLimits/read" } },
      "mapping": { "json": { "quotas": [{ "kind": "session", "at": "$.result.primary", "usedPercent": "usedPercent" }] } },
      "requiresFiles": ["~/.codex/auth.json"],
      "verifyBeforeBackground": true,
      "fallback": "tty"
    }
    """

    private func definition(_ json: String = rpc) throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data(json.utf8))
    }

    private func patch(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    // MARK: - Round trip

    @Test
    func `a definition survives being written out and read back`() throws {
        let rpc = try definition()

        let again = try JSONDecoder().decode(DataSourceDefinition.self, from: JSONEncoder().encode(rpc))

        #expect(again == rpc)
    }

    // MARK: - Merge patch (RFC 7396)

    @Test
    func `a patch replaces only the fields it names`() throws {
        let patched = try definition().patched(with: patch("""
        { "requiresFiles": ["{{account.codexHome}}/auth.json"] }
        """))

        #expect(patched.requiresFiles == ["{{account.codexHome}}/auth.json"])
        #expect(patched.kind == "rpc")
        #expect(patched.fallback?.to == "tty")
        #expect(patched.mapping == (try definition()).mapping)
    }

    @Test
    func `a null in the patch removes the field`() throws {
        let patched = try definition().patched(with: patch("""
        { "fallback": null, "verifyBeforeBackground": null }
        """))

        #expect(patched.fallback == nil)
        #expect(patched.verifyBeforeBackground == false)
    }

    @Test
    func `nested objects merge, arrays are replaced`() throws {
        let patched = try definition().patched(with: patch("""
        { "fetch": { "jsonRpc": { "args": ["-c", "x", "app-server"],
                                  "environment": { "set": { "CODEX_HOME": "/tmp/a" } } } } }
        """))

        guard case .jsonRpc(let call) = patched.fetch else {
            Issue.record("Expected a jsonRpc fetch")
            return
        }
        #expect(call.args == ["-c", "x", "app-server"])
        #expect(call.cli == "codex")
        #expect(call.call == "account/rateLimits/read")
        #expect(call.environment.set == ["CODEX_HOME": "/tmp/a"])
    }

    // MARK: - Filling a login's values

    @Test
    func `a login's values fill every account placeholder`() throws {
        let template = try definition().patched(with: patch("""
        { "requiresFiles": ["{{account.codexHome}}/auth.json"],
          "identity": { "field": "account", "equals": "{{account.chatgptAccountId}}" } }
        """))

        let filled = try template.filled(["codexHome": "/Users/me/codex-work", "chatgptAccountId": "acct-1"], scope: "account")

        #expect(filled.requiresFiles == ["/Users/me/codex-work/auth.json"])
        #expect(filled.identity?.equals == "acct-1")
        #expect(filled.unfilled(scope: "account").isEmpty)
    }

    @Test
    func `other placeholders are left for the fetch`() throws {
        let template = try definition("""
        { "kind": "api",
          "fetch": { "http": { "url": "https://example.com", "headers": { "Authorization": "Bearer {{token}}" } } },
          "mapping": { "json": { "quotas": [] } } }
        """)

        let filled = try template.filled(["codexHome": "/tmp"], scope: "account")

        guard case .http(let request) = filled.fetch else {
            Issue.record("Expected an http fetch")
            return
        }
        #expect(request.headers["Authorization"] == "Bearer {{token}}")
    }

    @Test
    func `a value the login doesn't have stays visible as unfilled`() throws {
        let template = try definition().patched(with: patch("""
        { "requiresFiles": ["{{account.codexHome}}/auth.json"] }
        """))

        let filled = try template.filled([:], scope: "account")

        #expect(filled.unfilled(scope: "account") == ["codexHome"])
    }
}
