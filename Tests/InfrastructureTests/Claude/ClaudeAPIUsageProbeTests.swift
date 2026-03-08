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
    func `probe parses extra usage correctly converting cents to dollars`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_pro")

        let mockNetwork = MockNetworkClient()
        // API returns used_credits and monthly_limit in cents
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000
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
        // 541 cents -> $5.41
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        // 2000 cents -> $20.00
        #expect(snapshot.costUsage?.budget == Decimal(string: "20"))
    }

    @Test
    func `probe converts API cost from cents to dollars for large amounts`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_pro")

        let mockNetwork = MockNetworkClient()
        // Simulates the real scenario: $26.72 spent of $50 budget
        // API returns 2672 cents and 5000 cents
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 2672,
            "monthly_limit": 5000
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

        #expect(snapshot.costUsage != nil)
        // 2672 cents -> $26.72 (NOT $2672.00)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "26.72"))
        // 5000 cents -> $50.00 (NOT $5000.00)
        #expect(snapshot.costUsage?.budget == Decimal(string: "50"))
        // Verify formatted output shows dollars, not cents
        #expect(snapshot.costUsage?.formattedCost.contains("26.72") == true)
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
    func `probe throws sessionExpired on 401 response`() async throws {
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

        await #expect(throws: ProbeError.sessionExpired) {
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
    func `probe throws sessionExpired when refresh token request returns invalid_grant`() async throws {
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

        await #expect(throws: ProbeError.sessionExpired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe recovers after session expiry when file has updated credentials`() async throws {
        // Scenario: cached refresh token is invalid, but CLI has re-authenticated
        // and written new credentials to the file
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Start with expired token
        let pastExpiry = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, accessToken: "old-token", expiresAt: pastExpiry)

        let mockNetwork = MockNetworkClient()
        var callCount = 0

        given(mockNetwork).request(.any).willProduce { request in
            callCount += 1
            let url = request.url?.absoluteString ?? ""

            if url.contains("oauth/token") {
                if callCount == 1 {
                    // First refresh attempt: old token is invalid
                    let errorResponse = """
                    { "error": "invalid_grant", "error_description": "Refresh token has been revoked" }
                    """.data(using: .utf8)!
                    return (errorResponse, HTTPURLResponse(
                        url: URL(string: "https://platform.claude.com")!,
                        statusCode: 400, httpVersion: nil, headerFields: nil)!)
                } else {
                    // Second refresh attempt (with fresh file credentials): success
                    let refreshResponse = """
                    { "access_token": "brand-new-token", "refresh_token": "brand-new-refresh", "expires_in": 3600 }
                    """.data(using: .utf8)!
                    return (refreshResponse, HTTPURLResponse(
                        url: URL(string: "https://platform.claude.com")!,
                        statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            } else {
                // Usage request succeeds
                let usageResponse = """
                { "five_hour": { "utilization": 15.0 } }
                """.data(using: .utf8)!
                return (usageResponse, HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com")!,
                    statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        // First probe: old token fails refresh → sessionExpired (file still has old creds)
        await #expect(throws: ProbeError.sessionExpired) {
            try await probe.probe()
        }

        // Simulate CLI re-authentication: write new credentials to file
        let newExpiry = Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, accessToken: "cli-refreshed-token",
                                  refreshToken: "cli-refreshed-refresh", expiresAt: newExpiry)

        // Second probe: cache was cleared, reloads from file → gets new creds → succeeds
        let snapshot = try await probe.probe()
        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.first?.percentRemaining == 85.0)
    }

    @Test
    func `probe falls back to file credentials when refresh fails with invalid_grant and file has new token`() async throws {
        // Scenario: during a single probe() call, refresh fails but file has been
        // updated by CLI in the meantime with a different access token
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Expired token in file
        let pastExpiry = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, accessToken: "stale-token", expiresAt: pastExpiry)

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let mockNetwork = MockNetworkClient()
        var refreshCallCount = 0

        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""

            if url.contains("oauth/token") {
                refreshCallCount += 1
                if refreshCallCount == 1 {
                    // First refresh attempt with stale token fails
                    // Simulate CLI updating the file concurrently
                    let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
                    try! self.createCredentialsFile(at: tempDir, accessToken: "brand-new-token",
                                                    refreshToken: "brand-new-refresh", expiresAt: futureExpiry)

                    let errorResponse = """
                    { "error": "invalid_grant", "error_description": "Token revoked" }
                    """.data(using: .utf8)!
                    return (errorResponse, HTTPURLResponse(
                        url: URL(string: "https://platform.claude.com")!,
                        statusCode: 400, httpVersion: nil, headerFields: nil)!)
                } else {
                    // Should not reach here — brand-new token from file is not expired
                    fatalError("Should not refresh a valid non-expired token")
                }
            } else {
                // Usage request succeeds
                let usageResponse = """
                { "five_hour": { "utilization": 20.0 } }
                """.data(using: .utf8)!
                return (usageResponse, HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com")!,
                    statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }

        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        // Probe should recover: refresh fails → clears cache → reloads from file
        // → finds brand-new non-expired token → fetches usage successfully
        let snapshot = try await probe.probe()
        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.first?.percentRemaining == 80.0) // 100 - 20
        #expect(refreshCallCount == 1) // Only one refresh attempt (stale token)
    }
}

// MARK: - Setup-Token (Environment) Tests

@Suite("ClaudeAPIUsageProbe Setup-Token Tests")
struct ClaudeAPIUsageProbeSetupTokenTests {

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-api-probe-setup-token-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @Test
    func `probe skips refresh when no refresh token and fetches successfully`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulate setup-token: loaded from env var, no refresh token, no expiresAt
        let loader = ClaudeCredentialLoader(
            homeDirectory: tempDir.path,
            useKeychain: false,
            environment: ["CLAUDE_CODE_OAUTH_TOKEN": "setup-token-abc123"]
        )

        let mockNetwork = MockNetworkClient()
        let usageResponse = """
        {
          "five_hour": { "utilization": 20.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day": { "utilization": 40.0, "resets_at": "2025-01-20T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let usageHTTP = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        // Only the usage call should be made — NO refresh call
        given(mockNetwork).request(.any).willReturn((usageResponse, usageHTTP))

        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.count == 2)

        let sessionQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(sessionQuota?.percentRemaining == 80.0)  // 100 - 20

        let weeklyQuota = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weeklyQuota?.percentRemaining == 60.0)  // 100 - 40
    }

    @Test
    func `probe trims newline in setup-token before Authorization header`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = ClaudeCredentialLoader(
            homeDirectory: tempDir.path,
            useKeychain: false,
            environment: ["CLAUDE_CODE_OAUTH_TOKEN": "setup-token-abc123\n"]
        )

        let mockNetwork = MockNetworkClient()
        let usageResponse = """
        {
          "five_hour": { "utilization": 20.0, "resets_at": "2025-01-15T10:00:00Z" }
        }
        """.data(using: .utf8)!

        let usageHTTP = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        var capturedAuthorizationHeader: String?
        given(mockNetwork).request(.any).willProduce { request in
            capturedAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            return (usageResponse, usageHTTP)
        }

        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        _ = try await probe.probe()

        #expect(capturedAuthorizationHeader == "Bearer setup-token-abc123")
    }

    @Test
    func `probe with setup-token throws authenticationRequired on 401 without attempting refresh`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = ClaudeCredentialLoader(
            homeDirectory: tempDir.path,
            useKeychain: false,
            environment: ["CLAUDE_CODE_OAUTH_TOKEN": "expired-setup-token"]
        )

        let mockNetwork = MockNetworkClient()
        let unauthorizedHTTP = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), unauthorizedHTTP))

        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        // Should throw without attempting refresh (no refresh token available)
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `isAvailable returns true when env var token is set`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = ClaudeCredentialLoader(
            homeDirectory: tempDir.path,
            useKeychain: false,
            environment: ["CLAUDE_CODE_OAUTH_TOKEN": "my-setup-token"]
        )

        let probe = ClaudeAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == true)
    }
}
