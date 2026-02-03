import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("ClaudeCredentialLoader Tests")
struct ClaudeCredentialLoaderTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-credential-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createCredentialsFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String = "test-refresh-token",
        expiresAt: Double? = nil,
        subscriptionType: String? = nil
    ) throws {
        let claudeDir = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        var oauthDict: [String: Any] = [
            "accessToken": accessToken,
            "refreshToken": refreshToken
        ]
        if let expiresAt {
            oauthDict["expiresAt"] = expiresAt
        }
        if let subscriptionType {
            oauthDict["subscriptionType"] = subscriptionType
        }

        let credentials: [String: Any] = [
            "claudeAiOauth": oauthDict
        ]

        let data = try JSONSerialization.data(withJSONObject: credentials, options: [.prettyPrinted])
        let filePath = claudeDir.appendingPathComponent(".credentials.json")
        try data.write(to: filePath)
    }

    // MARK: - Credential Loading Tests

    @Test
    func `loadCredentials returns nil when file does not exist`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Disable keychain to test file-only path
        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials returns credentials from file`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createCredentialsFile(
            at: tempDir,
            accessToken: "my-access-token",
            refreshToken: "my-refresh-token",
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
            subscriptionType: "claude_max"
        )

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(result?.oauth.accessToken == "my-access-token")
        #expect(result?.oauth.refreshToken == "my-refresh-token")
        #expect(result?.oauth.subscriptionType == "claude_max")
        #expect(result?.source == .file)
    }

    @Test
    func `loadCredentials returns nil when credentials file has empty accessToken`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createCredentialsFile(at: tempDir, accessToken: "", refreshToken: "refresh")

        // Disable keychain to test file-only path
        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials handles malformed JSON gracefully`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let claudeDir = tempDir.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let filePath = claudeDir.appendingPathComponent(".credentials.json")
        try "not valid json".write(to: filePath, atomically: true, encoding: .utf8)

        // Disable keychain to test file-only path
        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    @Test
    func `loadCredentials handles missing claudeAiOauth field`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let claudeDir = tempDir.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let filePath = claudeDir.appendingPathComponent(".credentials.json")
        let data = try JSONSerialization.data(withJSONObject: ["someOtherKey": "value"], options: [])
        try data.write(to: filePath)

        // Disable keychain to test file-only path
        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let credentials = loader.loadCredentials()

        #expect(credentials == nil)
    }

    // MARK: - Token Expiry Tests

    @Test
    func `needsRefresh returns true when token is expired`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Token expired 1 hour ago
        let pastTime = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: pastTime)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(result!.oauth) == true)
    }

    @Test
    func `needsRefresh returns true when token expires within 5 minutes`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Token expires in 4 minutes (less than 5 minute buffer)
        let nearFuture = Date().addingTimeInterval(4 * 60).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: nearFuture)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(result!.oauth) == true)
    }

    @Test
    func `needsRefresh returns false when token has more than 5 minutes left`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Token expires in 1 hour
        let futureTime = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureTime)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(result!.oauth) == false)
    }

    @Test
    func `needsRefresh returns true when expiresAt is missing`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createCredentialsFile(at: tempDir, expiresAt: nil)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path)
        let result = loader.loadCredentials()

        #expect(result != nil)
        #expect(loader.needsRefresh(result!.oauth) == true)
    }

    // MARK: - Credential Saving Tests

    @Test
    func `saveCredentials updates file correctly`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createCredentialsFile(
            at: tempDir,
            accessToken: "old-token",
            refreshToken: "old-refresh"
        )

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path)
        var result = loader.loadCredentials()!

        // Update the token
        result.oauth.accessToken = "new-token"
        result.oauth.refreshToken = "new-refresh"
        result.oauth.expiresAt = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000

        loader.saveCredentials(result)

        // Reload and verify
        let reloaded = loader.loadCredentials()
        #expect(reloaded?.oauth.accessToken == "new-token")
        #expect(reloaded?.oauth.refreshToken == "new-refresh")
    }
}
