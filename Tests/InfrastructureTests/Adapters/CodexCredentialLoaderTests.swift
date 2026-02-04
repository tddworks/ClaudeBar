import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("CodexCredentialLoader Tests")
struct CodexCredentialLoaderTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-credential-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String = "test-refresh-token",
        accountId: String? = nil,
        lastRefresh: String? = nil,
        apiKey: String? = nil
    ) throws {
        let codexDir = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        var tokens: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken
        ]
        if let accountId {
            tokens["account_id"] = accountId
        }

        var auth: [String: Any] = [
            "tokens": tokens
        ]
        if let lastRefresh {
            auth["last_refresh"] = lastRefresh
        }
        if let apiKey {
            auth["OPENAI_API_KEY"] = apiKey
        }

        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        let filePath = codexDir.appendingPathComponent("auth.json")
        try data.write(to: filePath)
    }

    // MARK: - Credential Loading Tests

    @Test
    func `loadCredentials returns nil when file does not exist`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials returns credentials from file`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(
            at: tempDir,
            accessToken: "my-access-token",
            refreshToken: "my-refresh-token",
            accountId: "acc-123"
        )

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(result?.accessToken == "my-access-token")
        #expect(result?.refreshToken == "my-refresh-token")
        #expect(result?.accountId == "acc-123")
    }

    @Test
    func `loadCredentials returns nil when access token is empty`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accessToken: "")

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials handles malformed JSON gracefully`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let filePath = codexDir.appendingPathComponent("auth.json")
        try "not valid json".write(to: filePath, atomically: true, encoding: .utf8)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials handles missing tokens field`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let filePath = codexDir.appendingPathComponent("auth.json")
        let data = try JSONSerialization.data(withJSONObject: ["someOtherKey": "value"], options: [])
        try data.write(to: filePath)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials detects API key auth`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let codexDir = tempDir.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let filePath = codexDir.appendingPathComponent("auth.json")
        let auth: [String: Any] = ["OPENAI_API_KEY": "sk-test-key"]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [])
        try data.write(to: filePath)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let credentials = loader.loadCredentials()

        // API key auth should return nil (not usable for usage API)
        #expect(credentials == nil)
    }

    // MARK: - Token Refresh Need Tests

    @Test
    func `needsRefresh returns true when lastRefresh is nil`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, lastRefresh: nil)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(lastRefresh: result?.lastRefresh) == true)
    }

    @Test
    func `needsRefresh returns true when lastRefresh is older than 8 days`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 9 days ago
        let oldDate = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldDateStr = formatter.string(from: oldDate)

        try createAuthFile(at: tempDir, lastRefresh: oldDateStr)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(lastRefresh: result?.lastRefresh) == true)
    }

    @Test
    func `needsRefresh returns false when lastRefresh is recent`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1 day ago
        let recentDate = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recentDateStr = formatter.string(from: recentDate)

        try createAuthFile(at: tempDir, lastRefresh: recentDateStr)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(lastRefresh: result?.lastRefresh) == false)
    }

    // MARK: - Credential Saving Tests

    @Test
    func `saveCredentials updates file correctly`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(
            at: tempDir,
            accessToken: "old-token",
            refreshToken: "old-refresh"
        )

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        var result = loader.loadCredentials()!

        // Update the tokens
        result.accessToken = "new-token"
        result.refreshToken = "new-refresh"
        result.lastRefresh = ISO8601DateFormatter().string(from: Date())

        loader.saveCredentials(result)

        // Reload and verify
        let reloaded = loader.loadCredentials()
        #expect(reloaded?.accessToken == "new-token")
        #expect(reloaded?.refreshToken == "new-refresh")
        #expect(reloaded?.lastRefresh != nil)
    }
}
