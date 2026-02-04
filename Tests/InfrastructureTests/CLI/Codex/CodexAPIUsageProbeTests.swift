import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("CodexAPIUsageProbe Tests")
struct CodexAPIUsageProbeTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String = "test-refresh-token",
        accountId: String? = nil,
        lastRefresh: String? = nil
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
        } else {
            // Set a recent last_refresh so we don't trigger a proactive refresh
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            auth["last_refresh"] = formatter.string(from: Date())
        }

        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        let filePath = codexDir.appendingPathComponent("auth.json")
        try data.write(to: filePath)
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when credentials exist`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when credentials missing`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Authentication Tests

    @Test
    func `probe throws authenticationRequired when no credentials`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    // MARK: - Response Parsing Tests (Headers)

    @Test
    func `probe parses session usage from response headers`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "rate_limit": {
            "primary_window": {
              "reset_after_seconds": 3600
            }
          }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-codex-primary-used-percent": "25.5",
                "x-codex-secondary-used-percent": "45.0"
            ]
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "codex")

        let sessionQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(sessionQuota != nil)
        #expect(sessionQuota?.percentRemaining == 74.5) // 100 - 25.5

        let weeklyQuota = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weeklyQuota != nil)
        #expect(weeklyQuota?.percentRemaining == 55.0) // 100 - 45.0
    }

    // MARK: - Response Parsing Tests (Body Fallback)

    @Test
    func `probe falls back to body when headers not present`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 30.0,
              "reset_at": 1705312800
            },
            "secondary_window": {
              "used_percent": 60.0,
              "reset_after_seconds": 432000
            }
          }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        let sessionQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(sessionQuota != nil)
        #expect(sessionQuota?.percentRemaining == 70.0) // 100 - 30

        let weeklyQuota = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weeklyQuota != nil)
        #expect(weeklyQuota?.percentRemaining == 40.0) // 100 - 60
    }

    // MARK: - Plan Type Tests

    @Test
    func `probe parses plan type from response body`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 10.0
            }
          },
          "plan_type": "plus"
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.accountTier == .custom("PLUS"))
    }

    // MARK: - Credits Tests

    @Test
    func `probe parses credits from response header`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 10.0
            }
          }
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-codex-credits-balance": "750.0"
            ]
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == 250) // 1000 - 750
        #expect(snapshot.costUsage?.budget == 1000)
    }

    // MARK: - Empty Response Tests

    @Test
    func `probe handles empty response with no usage data`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let responseJSON = "{}".data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        // Should succeed but have no quotas
        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Error Handling Tests

    @Test
    func `probe throws sessionExpired on 401 response`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.sessionExpired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed on invalid JSON`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn(("not json".data(using: .utf8)!, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on network error`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willThrow(URLError(.notConnectedToInternet))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on HTTP 500`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }
}

// MARK: - Token Refresh Tests

@Suite("CodexAPIUsageProbe Token Refresh Tests")
struct CodexAPIUsageProbeTokenRefreshTests {

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-probe-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String = "test-refresh-token",
        lastRefresh: String? = nil
    ) throws {
        let codexDir = directory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        var auth: [String: Any] = [
            "tokens": [
                "access_token": accessToken,
                "refresh_token": refreshToken
            ] as [String: Any]
        ]
        if let lastRefresh {
            auth["last_refresh"] = lastRefresh
        }

        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        let filePath = codexDir.appendingPathComponent("auth.json")
        try data.write(to: filePath)
    }

    @Test
    func `probe refreshes token when lastRefresh is old and retries`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // last_refresh 9 days ago → needs refresh
        let oldDate = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldDateStr = formatter.string(from: oldDate)

        try createAuthFile(at: tempDir, accessToken: "old-token", lastRefresh: oldDateStr)

        let mockNetwork = MockNetworkClient()

        // First call: refresh token request (form-urlencoded)
        let refreshResponse = """
        {
          "access_token": "new-token",
          "refresh_token": "new-refresh-token"
        }
        """.data(using: .utf8)!

        let refreshHTTP = HTTPURLResponse(
            url: URL(string: "https://auth.openai.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        // Second call: usage request with new token
        let usageResponse = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 10.0 }
          }
        }
        """.data(using: .utf8)!

        let usageHTTP = HTTPURLResponse(
            url: URL(string: "https://chatgpt.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth/token") {
                return (refreshResponse, refreshHTTP)
            } else {
                return (usageResponse, usageHTTP)
            }
        }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "codex")
        #expect(snapshot.quotas.first?.percentRemaining == 90.0) // 100 - 10
    }

    @Test
    func `probe throws sessionExpired when refresh returns refresh_token_expired`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Trigger refresh by setting old last_refresh
        let oldDate = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try createAuthFile(at: tempDir, lastRefresh: formatter.string(from: oldDate))

        let mockNetwork = MockNetworkClient()

        let errorResponse = """
        { "error": { "code": "refresh_token_expired" } }
        """.data(using: .utf8)!

        let errorHTTP = HTTPURLResponse(
            url: URL(string: "https://auth.openai.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((errorResponse, errorHTTP))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.sessionExpired) {
            try await probe.probe()
        }
    }
}
