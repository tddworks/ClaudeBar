import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("GrokUsageProbe Tests")
struct GrokUsageProbeTests {

    // MARK: - Test Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createAuthFile(
        at directory: URL,
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAt: String = "2099-01-01T00:00:00.000000Z"
    ) throws {
        let grokDir = directory.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokDir, withIntermediateDirectories: true)

        var entry: [String: Any] = [
            "key": accessToken,
            "auth_mode": "oidc",
            "email": "user@example.com",
            "expires_at": expiresAt,
            "oidc_issuer": "https://auth.x.ai",
            "oidc_client_id": "client-123"
        ]
        if let refreshToken {
            entry["refresh_token"] = refreshToken
        }

        let auth: [String: Any] = ["https://auth.x.ai::client-123": entry]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        try data.write(to: grokDir.appendingPathComponent("auth.json"))
    }

    private static let billingJSON = """
    {
      "config": {
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-07-23T05:09:24.881042+00:00",
          "end": "2026-07-30T05:09:24.881042+00:00"
        },
        "creditUsagePercent": 96.0,
        "productUsage": [
          {"product": "GrokBuild", "usagePercent": 84.0}
        ]
      }
    }
    """.data(using: .utf8)!

    private func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when credentials exist`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when credentials missing`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Tests

    @Test
    func `probe throws authenticationRequired when no credentials`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe returns snapshot with account email on success`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn((Self.billingJSON, httpResponse(200)))

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "grok")
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
        #expect(snapshot.quota(for: .modelSpecific("Build"))?.percentRemaining == 16.0)
    }

    @Test
    func `probe refreshes token on 401 and retries`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accessToken: "stale-token")

        let mockNetwork = MockNetworkClient()
        let refreshResponse = """
        {"access_token": "fresh-token", "refresh_token": "fresh-refresh-token", "expires_in": 3600}
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2/token") {
                return (refreshResponse, self.httpResponse(200))
            }
            let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if token.contains("fresh-token") {
                return (Self.billingJSON, self.httpResponse(200))
            }
            return (Data(), self.httpResponse(401))
        }

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.quota(for: .weekly)?.percentRemaining == 4.0)
        // The refreshed token was written back for the next probe
        #expect(loader.loadCredentials()?.accessToken == "fresh-token")
        #expect(loader.loadCredentials()?.refreshToken == "fresh-refresh-token")
    }

    @Test
    func `probe proactively refreshes expired token`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir, accessToken: "expired-token", expiresAt: "2020-01-01T00:00:00.000000Z")

        let mockNetwork = MockNetworkClient()
        let refreshResponse = """
        {"access_token": "fresh-token", "expires_in": 3600}
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2/token") {
                return (refreshResponse, self.httpResponse(200))
            }
            return (Self.billingJSON, self.httpResponse(200))
        }

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.count == 2)
        #expect(loader.loadCredentials()?.accessToken == "fresh-token")
    }

    @Test
    func `probe throws sessionExpired when refresh is rejected`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Expired token forces a refresh; the refresh endpoint rejects it
        try createAuthFile(at: tempDir, expiresAt: "2020-01-01T00:00:00.000000Z")

        let mockNetwork = MockNetworkClient()
        let errorResponse = """
        {"error": "invalid_grant"}
        """.data(using: .utf8)!
        given(mockNetwork).request(.any).willReturn((errorResponse, httpResponse(400)))

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.sessionExpired()) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws sessionExpired when token stays rejected after refresh`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let refreshResponse = """
        {"access_token": "fresh-token", "expires_in": 3600}
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2/token") {
                return (refreshResponse, self.httpResponse(200))
            }
            return (Data(), self.httpResponse(401))
        }

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.sessionExpired()) {
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

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

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
        given(mockNetwork).request(.any).willReturn((Data(), httpResponse(500)))

        let loader = GrokCredentialLoader(homeDirectory: tempDir.path)
        let probe = GrokUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.executionFailed("HTTP error: 500")) {
            try await probe.probe()
        }
    }
}
