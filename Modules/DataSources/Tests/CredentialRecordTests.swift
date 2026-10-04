import Foundation
import Testing
@testable import DataSources

/// `jsonFile.record` — a login file holding several records: the one that
/// can be refreshed and lasts longest answers, and a refreshed token goes
/// back into that record only. `defaults` fill what a record lacks.
@Suite
struct CredentialRecordTests {
    private func file(_ json: String) throws -> (JSONFileReader, URL, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("auth.json")
        try Data(json.utf8).write(to: url)
        let credential = try JSONDecoder().decode(JSONFileCredential.self, from: Data("""
        {"path":"\(url.path)","token":"$.key","refreshToken":"$.refresh_token","expiresAt":"$.expires_at",
         "issuer":"$.issuer","record":{"prefer":"refreshToken","latest":"expiresAt"},
         "defaults":{"issuer":"https://auth.acme.test"}}
        """.utf8))
        return (JSONFileReader(file: credential, homeDirectory: root, environment: { _ in nil }), url,
                { try? FileManager.default.removeItem(at: root) })
    }

    private let three = """
    {"a":{"key":"no-refresh","expires_at":"2099-01-01T00:00:00Z"},
     "b":{"key":"short","refresh_token":"r-b","expires_at":"2026-01-01T00:00:00.123456Z"},
     "c":{"key":"long","refresh_token":"r-c","expires_at":"2027-01-01T00:00:00Z","issuer":"https://login.acme.test/"}}
    """

    @Test
    func `the record that can be refreshed and lasts longest answers`() throws {
        let (reader, _, cleanUp) = try file(three)
        defer { cleanUp() }
        let found = try #require(try reader.find())
        #expect(found.credential.token == "long")
        #expect(found.credential["issuer"] == "https://login.acme.test/")
    }

    @Test
    func `a record without a value gets the default, which is never written back`() throws {
        let (reader, url, cleanUp) = try file(#"{"only":{"key":"k","refresh_token":"r"}}"#)
        defer { cleanUp() }
        var found = try #require(try reader.find())
        #expect(found.credential["issuer"] == "https://auth.acme.test")

        found.credential["token"] = "renewed"
        found.save?(found.credential)

        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]]
        #expect(written?["only"]?["key"] as? String == "renewed")
        #expect(written?["only"]?["issuer"] == nil)
    }

    @Test
    func `a refreshed token goes back into its own record, and every other record stays`() throws {
        let (reader, url, cleanUp) = try file(three)
        defer { cleanUp() }
        var found = try #require(try reader.find())

        found.credential["token"] = "renewed"
        found.credential["refreshToken"] = "r-c2"
        found.save?(found.credential)

        let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
        #expect(written["c"]?["key"] as? String == "renewed")
        #expect(written["c"]?["refresh_token"] as? String == "r-c2")
        #expect(written["b"]?["key"] as? String == "short")
        #expect(written["a"]?["key"] as? String == "no-refresh")
    }

    @Test
    func `a file with no usable record has no key`() throws {
        let (reader, _, cleanUp) = try file(#"{"a":{"email":"x"},"b":"not a record"}"#)
        defer { cleanUp() }
        #expect(try reader.find() == nil)
    }
}
