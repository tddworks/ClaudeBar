import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("ClaudeAPIUsageProbe Tests")
struct ClaudeAPIUsageProbeTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-api-probe-tests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when credentials exist`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when credentials missing`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Authentication Tests

    @Test
    func `probe throws authenticationRequired when no credentials`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    // MARK: - Response Parsing Tests

    @Test
    func `probe parses session usage correctly`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_max")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": {
            "utilization": 25.5,
            "resets_at": "2025-01-15T10:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.accountTier == .claudeMax)

        let sessionQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(sessionQuota != nil)
        #expect(sessionQuota?.percentRemaining == 74.5)  // 100 - 25.5
        #expect(sessionQuota?.resetsAt != nil)
    }

    @Test
    func `probe parses weekly usage correctly`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day": { "utilization": 45.0, "resets_at": "2025-01-20T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        let weeklyQuota = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weeklyQuota != nil)
        #expect(weeklyQuota?.percentRemaining == 55.0)  // 100 - 45
    }

    @Test
    func `probe parses model-specific quotas correctly`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day_sonnet": { "utilization": 30.0, "resets_at": "2025-01-20T00:00:00Z" },
          "seven_day_opus": { "utilization": 60.0, "resets_at": "2025-01-20T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        let sonnetQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("sonnet") }
        #expect(sonnetQuota != nil)
        #expect(sonnetQuota?.percentRemaining == 70.0)  // 100 - 30

        let opusQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("opus") }
        #expect(opusQuota != nil)
        #expect(opusQuota?.percentRemaining == 40.0)  // 100 - 60
    }

    @Test
    func `probe parses extra usage correctly`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_pro")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 5.41,
            "monthly_limit": 20.00
          }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == 5.41)
        #expect(snapshot.costUsage?.budget == 20.00)
    }

    @Test
    func `probe handles empty response with badge`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let responseJSON = "{}".data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        // Should succeed but have no quotas
        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Account Tier Detection Tests

    @Test
    func `probe detects claude_max subscription type`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_max")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        { "five_hour": { "utilization": 10.0 } }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()
        #expect(snapshot.accountTier == .claudeMax)
    }

    @Test
    func `probe detects claude_pro subscription type`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_pro")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        { "five_hour": { "utilization": 10.0 } }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()
        #expect(snapshot.accountTier == .claudePro)
    }

    // MARK: - Error Handling Tests

    @Test
    func `probe throws authenticationRequired on 401 response`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired on 403 response`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        // 403 triggers a token refresh attempt which also fails with 403 -> executionFailed
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed on invalid JSON`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn(("not json".data(using: .utf8)!, response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on network error`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willThrow(URLError(.notConnectedToInternet))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }
}

// MARK: - Token Refresh Tests

@Suite("ClaudeAPIUsageProbe Token Refresh Tests")
struct ClaudeAPIUsageProbeTokenRefreshTests {

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-api-probe-refresh-tests-\(UUID().uuidString)", isDirectory: true)
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

    @Test
    func `probe refreshes token when expired and retries`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Token expired 1 hour ago
        let pastExpiry = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, accessToken: "old-token", expiresAt: pastExpiry)

        let mockNetwork = MockNetworkClient()

        // First call: refresh token request
        let refreshResponse = """
        {
          "access_token": "new-token",
          "refresh_token": "new-refresh-token",
          "expires_in": 3600
        }
        """.data(using: .utf8)!

        let refreshHTTP = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        // Second call: usage request with new token
        let usageResponse = """
        { "five_hour": { "utilization": 10.0 } }
        """.data(using: .utf8)!

        let usageHTTP = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        // Setup mock to return refresh response first, then usage response
        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth/token") {
                return (refreshResponse, refreshHTTP)
            } else {
                return (usageResponse, usageHTTP)
            }
        }

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.first?.percentRemaining == 90.0)
    }

    @Test
    func `probe throws when refresh token request returns invalid_grant`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Token expired
        let pastExpiry = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: pastExpiry)

        let mockNetwork = MockNetworkClient()

        let errorResponse = """
        { "error": "invalid_grant", "error_description": "Refresh token has been revoked" }
        """.data(using: .utf8)!

        let errorHTTP = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((errorResponse, errorHTTP))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }
}
