import Foundation
import Testing
@testable import DataSources

@Suite
struct CredentialReadersTests {

    private let home = URL(fileURLWithPath: "/Users/someone")

    // MARK: - KeychainReader.decode

    @Test
    func `should read a keychain login the Mac hands back hex-encoded`() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"hex-token"}}"#
        let hex = json.utf8.map { String(format: "%02x", $0) }.joined()

        let decoded = try #require(KeychainReader.decode(hex))

        #expect(String(data: decoded, encoding: .utf8) == json)
    }

    @Test
    func `should read a keychain login stored as plain JSON as it is`() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"plain-token"}}"#

        let decoded = try #require(KeychainReader.decode(json))

        #expect(String(data: decoded, encoding: .utf8) == json)
    }

    // MARK: - KeychainReader write-back

    @Test
    func `should save a renewed keychain login over the same item as one printable line, keeping its other fields`() throws {
        let password = """
        {
          "claudeAiOauth": {
            "accessToken": "old-token",
            "expiresAt": 1748276587173,
            "scopes": ["user:inference", "user:profile"]
          }
        }
        """
        let calls = SecurityCalls()
        let reader = KeychainReader(
            item: KeychainCredential(service: "Some-credentials", fields: [
                "token": "$.claudeAiOauth.accessToken",
                "expiresAt": "$.claudeAiOauth.expiresAt",
            ]),
            security: { arguments in
                calls.append(arguments)
                return arguments.first == "find-generic-password" ? (0, password) : (0, "")
            }
        )
        let found = try #require(try reader.find())
        var refreshed = found.credential
        refreshed["token"] = "refreshed-token"
        refreshed["expiresAt"] = "1800000000000"

        found.save?(refreshed)

        let write = try #require(calls.all.last)
        #expect(Array(write.dropLast()) == ["add-generic-password", "-U", "-s", "Some-credentials", "-a", NSUserName(), "-w"])
        let payload = try #require(write.last)
        // `security find-generic-password -w` hex-encodes any password holding a
        // byte outside printable ASCII, so the payload must stay printable.
        #expect(payload.allSatisfy { $0.isASCII && $0.asciiValue.map { (0x20...0x7e).contains($0) } == true })
        #expect(!payload.contains("\n"))
        let saved = try #require(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let oauth = try #require(saved["claudeAiOauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "refreshed-token")
        #expect((oauth["expiresAt"] as? NSNumber)?.int64Value == 1_800_000_000_000)
        #expect(oauth["scopes"] as? [String] == ["user:inference", "user:profile"])
    }

    @Test
    func `should find no key when the keychain item isn't there`() throws {
        let reader = KeychainReader(
            item: KeychainCredential(service: "Missing", fields: ["token": "$.token"]),
            security: { _ in (44, "") }
        )

        #expect(try reader.find() == nil)
    }

    // MARK: - EnvironmentReader

    @Test
    func `should use an environment key without surrounding whitespace, never save it, and find none when it is empty`() throws {
        let trimmed = EnvironmentReader(name: "KEY", environment: { _ in "  sk-1\n" })
        let empty = EnvironmentReader(name: "KEY", environment: { _ in "" })

        #expect(try trimmed.find()?.credential.token == "sk-1")
        #expect(try trimmed.find()?.save == nil)
        #expect(try empty.find() == nil)
    }

    // MARK: - Paths.expand

    @Test
    func `should place a path starting with a tilde under the home folder and leave an absolute path alone`() {
        #expect(Paths.expand("~/.claude/.credentials.json", homeDirectory: home, environment: { _ in nil })
            == "/Users/someone/.claude/.credentials.json")
        #expect(Paths.expand("~", homeDirectory: home, environment: { _ in nil }) == "/Users/someone")
        #expect(Paths.expand("/etc/absolute.json", homeDirectory: home, environment: { _ in nil }) == "/etc/absolute.json")
    }

    @Test
    func `should place a path under the folder a variable names when the variable is set`() {
        let path = Paths.expand("${CONFIG_DIR:-~}/.claude.json", homeDirectory: home, environment: { $0 == "CONFIG_DIR" ? "/custom" : nil })

        #expect(path == "/custom/.claude.json")
    }

    @Test
    func `should place a path under its default folder when the variable is unset or empty`() {
        let unset = Paths.expand("${CONFIG_DIR:-~}/.claude.json", homeDirectory: home, environment: { _ in nil })
        let empty = Paths.expand("${CONFIG_DIR:-~}/.claude.json", homeDirectory: home, environment: { _ in "" })

        #expect(unset == "/Users/someone/.claude.json")
        #expect(empty == "/Users/someone/.claude.json")
    }

    // MARK: - CredentialDocument.values

    @Test
    func `should read a login's granted scopes as the one line a refresh asks for`() throws {
        let document: [String: Any] = ["oauth": ["scopes": ["user:profile", "user:mcp_servers"]] as [String: Any]]

        let values = CredentialDocument.values(["scopes": "$.oauth.scopes#joined"], in: document)

        #expect(values["scopes"] == "user:profile user:mcp_servers")
    }

    @Test
    func `should name no scopes when the login has none, so the provider's own are asked for`() throws {
        let empty: [String: Any] = ["oauth": ["scopes": []] as [String: Any]]

        #expect(CredentialDocument.values(["scopes": "$.oauth.scopes#joined"], in: empty).isEmpty)
        #expect(CredentialDocument.values(["scopes": "$.oauth.scopes#joined"], in: [:]).isEmpty)
    }

    // MARK: - CredentialDocument.updated

    private let fields = [
        "token": "$.oauth.accessToken",
        "refreshToken": "$.oauth.refreshToken",
        "expiresAt": "$.oauth.expiresAt",
    ]

    @Test
    func `should keep each saved value's type when a renewed login is written back`() throws {
        let document: [String: Any] = ["oauth": ["accessToken": "old", "expiresAt": 1000, "refreshToken": "r"] as [String: Any]]

        let updated = CredentialDocument.updated(
            document,
            with: Credential(["token": "new", "expiresAt": "2000", "refreshToken": "1234"]),
            fields: fields
        )

        let oauth = try #require(updated["oauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new")
        #expect((oauth["expiresAt"] as? NSNumber)?.intValue == 2000)
        // A string that looks like a number stays a string.
        #expect(oauth["refreshToken"] as? String == "1234")
    }

    @Test
    func `should write a new expiry time as a number when the login file had none`() throws {
        let document: [String: Any] = ["oauth": ["accessToken": "old"]]

        let updated = CredentialDocument.updated(document, with: Credential(["token": "new", "expiresAt": "2000"]), fields: fields)

        let oauth = try #require(updated["oauth"] as? [String: Any])
        #expect(oauth["expiresAt"] is NSNumber)
        #expect((oauth["expiresAt"] as? NSNumber)?.intValue == 2000)
    }

    @Test
    func `should keep every field the definition doesn't name and add none when a renewed login is written back`() throws {
        let document: [String: Any] = [
            "oauth": ["accessToken": "old", "scopes": ["a", "b"]] as [String: Any],
            "other": "kept",
        ]

        let updated = CredentialDocument.updated(
            document,
            with: Credential(["token": "new", "refreshedAt": "2026-01-01T00:00:00Z"]),
            fields: fields
        )

        let oauth = try #require(updated["oauth"] as? [String: Any])
        #expect(oauth["scopes"] as? [String] == ["a", "b"])
        #expect(updated["other"] as? String == "kept")
        // A credential value with no field in the file is not written.
        #expect(oauth["refreshedAt"] == nil)
        #expect(updated["refreshedAt"] == nil)
    }

    // MARK: - JSONFileReader write-back

    @Test
    func `should leave a login's granted scopes as the list they were when a renewed login is saved back`() throws {
        let document: [String: Any] = ["oauth": ["accessToken": "old", "scopes": ["a", "b"]] as [String: Any]]
        let scopes = ["token": "$.oauth.accessToken", "scopes": "$.oauth.scopes#joined"]

        let updated = CredentialDocument.updated(document, with: Credential(["token": "new", "scopes": "a b"]), fields: scopes)

        let oauth = try #require(updated["oauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new")
        #expect(oauth["scopes"] as? [String] == ["a", "b"])
    }

    @Test
    func `should keep a login file's other fields and number types when a renewed login is saved into it`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("readers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original: [String: Any] = ["oauth": ["accessToken": "old", "expiresAt": 1000, "scopes": ["x"]] as [String: Any]]
        try JSONSerialization.data(withJSONObject: original).write(to: directory.appendingPathComponent("auth.json"))
        let reader = JSONFileReader(
            file: JSONFileCredential(path: "~/auth.json", fields: fields),
            homeDirectory: directory,
            environment: { _ in nil }
        )
        let found = try #require(try reader.find())
        var refreshed = found.credential
        refreshed["token"] = "new"
        refreshed["expiresAt"] = "2000"

        found.save?(refreshed)

        let saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("auth.json"))) as? [String: Any])
        let oauth = try #require(saved["oauth"] as? [String: Any])
        #expect(oauth["accessToken"] as? String == "new")
        #expect((oauth["expiresAt"] as? NSNumber)?.intValue == 2000)
        #expect(oauth["scopes"] as? [String] == ["x"])
    }
}

/// Every `security` invocation, in order.
private final class SecurityCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String]] = []

    func append(_ arguments: [String]) {
        lock.withLock { calls.append(arguments) }
    }

    var all: [[String]] {
        lock.withLock { calls }
    }
}
