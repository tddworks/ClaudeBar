import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("GrokCredentialLoader Tests")
struct GrokCredentialLoaderTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-credential-loader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func writeAuthFile(at directory: URL, json: [String: Any]) throws {
        let grokDir = directory.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: grokDir.appendingPathComponent("auth.json"))
    }

    private func oidcEntry(
        key: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        email: String? = "user@example.com",
        expiresAt: String? = "2099-01-01T00:00:00.000000Z"
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "key": key,
            "auth_mode": "oidc",
            "oidc_issuer": "https://auth.x.ai",
            "oidc_client_id": "client-123"
        ]
        if let refreshToken { entry["refresh_token"] = refreshToken }
        if let email { entry["email"] = email }
        if let expiresAt { entry["expires_at"] = expiresAt }
        return entry
    }

    // MARK: - Loading Tests

    @Test
    func `loads credentials from oidc entry`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeAuthFile(at: tempDir, json: [
            "https://auth.x.ai::client-123": oidcEntry()
        ])

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials != nil)
        #expect(credentials?.accessToken == "test-access-token")
        #expect(credentials?.refreshToken == "test-refresh-token")
        #expect(credentials?.email == "user@example.com")
        #expect(credentials?.oidcIssuer == "https://auth.x.ai")
        #expect(credentials?.oidcClientId == "client-123")
        #expect(credentials?.entryKey == "https://auth.x.ai::client-123")
    }

    @Test
    func `returns nil when auth file missing`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)

        #expect(loader.loadCredentials() == nil)
    }

    @Test
    func `returns nil when no entry has a token`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeAuthFile(at: tempDir, json: [
            "https://auth.x.ai::client-123": ["key": "", "auth_mode": "oidc"]
        ])

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)

        #expect(loader.loadCredentials() == nil)
    }

    @Test
    func `prefers refreshable entry over api key entry`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeAuthFile(at: tempDir, json: [
            "https://accounts.x.ai/sign-in": ["key": "legacy-api-key"],
            "https://auth.x.ai::client-123": oidcEntry(key: "oidc-token")
        ])

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials?.accessToken == "oidc-token")
    }

    @Test
    func `treats empty refresh token as absent`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var entry = oidcEntry()
        entry["refresh_token"] = ""
        try writeAuthFile(at: tempDir, json: [
            "https://auth.x.ai::client-123": entry
        ])

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let credentials = try #require(loader.loadCredentials())

        #expect(credentials.refreshToken == nil)
    }

    // MARK: - Expiry Tests

    @Test
    func `needsRefresh true when token expired`() {
        let loader = GrokCredentialLoader()

        #expect(loader.needsRefresh(expiresAt: "2020-01-01T00:00:00.000000Z") == true)
    }

    @Test
    func `needsRefresh false when token valid`() {
        let loader = GrokCredentialLoader()

        #expect(loader.needsRefresh(expiresAt: "2099-01-01T00:00:00.000000Z") == false)
    }

    @Test
    func `needsRefresh false when no expiry recorded`() {
        let loader = GrokCredentialLoader()

        #expect(loader.needsRefresh(expiresAt: nil) == false)
    }

    // MARK: - Date Parsing Tests

    @Test
    func `parses microsecond fraction timestamps`() {
        let date = GrokCredentialLoader.parseDate("2026-07-26T21:03:09.138930Z")

        #expect(date != nil)
    }

    @Test
    func `parses timestamps with utc offset`() {
        let date = GrokCredentialLoader.parseDate("2026-07-23T05:09:24.881042+00:00")

        #expect(date != nil)
    }

    @Test
    func `parses timestamps without fraction`() {
        let date = GrokCredentialLoader.parseDate("2026-07-23T05:09:24Z")

        #expect(date != nil)
    }

    @Test
    func `returns nil for garbage timestamps`() {
        #expect(GrokCredentialLoader.parseDate("not a date") == nil)
        #expect(GrokCredentialLoader.parseDate(nil) == nil)
    }

    // MARK: - Save Tests

    @Test
    func `saveCredentials updates token fields and preserves the rest`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeAuthFile(at: tempDir, json: [
            "https://auth.x.ai::client-123": oidcEntry()
        ])

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        var credentials = try #require(loader.loadCredentials())

        credentials.accessToken = "new-token"
        credentials.refreshToken = "new-refresh-token"
        credentials.expiresAt = "2099-06-01T00:00:00.000Z"
        loader.saveCredentials(credentials)

        let reloaded = try #require(loader.loadCredentials())
        #expect(reloaded.accessToken == "new-token")
        #expect(reloaded.refreshToken == "new-refresh-token")
        #expect(reloaded.expiresAt == "2099-06-01T00:00:00.000Z")
        // Fields the refresh doesn't touch stay intact
        #expect(reloaded.email == "user@example.com")
        #expect(reloaded.oidcIssuer == "https://auth.x.ai")
    }
}
