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

    private func probe(responseJSON: String, subscriptionType: String = "claude_pro") async throws -> UsageSnapshot {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(
            at: tempDir,
            expiresAt: futureExpiry,
            subscriptionType: subscriptionType
        )

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((Data(responseJSON.utf8), response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        return try await probe.probe()
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

    // MARK: - Snapshot Cache (TTL) Tests

    @Test
    func `probe serves cached snapshot on subsequent calls within TTL`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_max")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": { "utilization": 25.0, "resets_at": "2025-01-15T10:00:00Z" }
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

        let first = try await probe.probe()
        let second = try await probe.probe()
        let third = try await probe.probe()

        // All three calls return the same cached snapshot...
        #expect(first.quotas.first?.percentRemaining == 75.0)
        #expect(second.quotas.first?.percentRemaining == 75.0)
        #expect(third.quotas.first?.percentRemaining == 75.0)
        // ...but only the first one actually hit the network.
        verify(mockNetwork).request(.any).called(1)
    }

    @Test
    func `probe bypasses cache when TTL is zero`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry, subscriptionType: "claude_max")

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": { "utilization": 25.0, "resets_at": "2025-01-15T10:00:00Z" }
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
        // TTL=0 means every entry is immediately stale, so every probe re-fetches.
        let probe = ClaudeAPIUsageProbe(
            credentialLoader: loader,
            networkClient: mockNetwork,
            snapshotCacheTTL: 0
        )

        _ = try await probe.probe()
        _ = try await probe.probe()

        verify(mockNetwork).request(.any).called(2)
    }

    // MARK: - Rate Limit (HTTP 429) Tests

    @Test
    func `probe throws rateLimited when API returns 429 with Retry-After seconds`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "120"]
        )!
        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let before = Date()
        do {
            _ = try await probe.probe()
            Issue.record("Expected rateLimited error to be thrown")
        } catch let error as ProbeError {
            guard case .rateLimited(let retryAt) = error else {
                Issue.record("Expected .rateLimited, got \(error)")
                return
            }
            let delta = retryAt.timeIntervalSince(before)
            #expect(delta >= 119 && delta <= 122)
        }
    }

    @Test
    func `probe defaults to 5 minute retry when 429 has no Retry-After header`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!
        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let before = Date()
        do {
            _ = try await probe.probe()
            Issue.record("Expected rateLimited error to be thrown")
        } catch let error as ProbeError {
            guard case .rateLimited(let retryAt) = error else {
                Issue.record("Expected .rateLimited, got \(error)")
                return
            }
            let delta = retryAt.timeIntervalSince(before)
            #expect(delta >= 299 && delta <= 302)
        }
    }

    @Test
    func `probe short-circuits subsequent calls within active rate-limit window`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "600"]
        )!
        given(mockNetwork).request(.any).willReturn((Data(), response))

        let loader = ClaudeCredentialLoader(homeDirectory: tempDir.path, useKeychain: false)
        let probe = ClaudeAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        // First call: hits the network and stores the rate-limit window
        _ = try? await probe.probe()
        // Second call: must throw immediately without re-hitting the network
        _ = try? await probe.probe()

        verify(mockNetwork).request(.any).called(1)
    }

    // MARK: - Retry-After Parsing Tests

    @Test
    func `parseRetryAfter accepts positive integer seconds`() {
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("120") == 120)
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("1") == 1)
    }

    @Test
    func `parseRetryAfter rejects zero seconds`() {
        // /api/oauth/usage has been observed returning Retry-After: 0 while
        // still 429ing (anthropics/claude-code#30930). Treat 0 as no usable
        // value so the caller applies its fallback window instead.
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("0") == nil)
    }

    @Test
    func `parseRetryAfter accepts HTTP-date in the future`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 2023-11-14 22:13:20 UTC + 60s = 2023-11-14 22:14:20 UTC
        let result = ClaudeAPIUsageProbe.parseRetryAfter(
            "Tue, 14 Nov 2023 22:14:20 GMT",
            now: now
        )
        #expect(result == 60)
    }

    @Test
    func `parseRetryAfter rejects past HTTP-dates`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = ClaudeAPIUsageProbe.parseRetryAfter(
            "Tue, 14 Nov 2023 22:00:00 GMT",
            now: now
        )
        #expect(result == nil)
    }

    @Test
    func `parseRetryAfter rejects malformed and empty values`() {
        #expect(ClaudeAPIUsageProbe.parseRetryAfter(nil) == nil)
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("") == nil)
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("   ") == nil)
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("not a number") == nil)
        #expect(ClaudeAPIUsageProbe.parseRetryAfter("-5") == nil)
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
    func `probe parses fable quota from scoped limits array`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        // Newer API responses report model limits via a generic "limits" array
        // (kind "weekly_scoped" + scope.model.display_name) instead of
        // dedicated seven_day_<model> fields.
        let responseJSON = """
        {
          "five_hour": { "utilization": 23.0, "resets_at": "2026-07-02T07:09:59Z" },
          "seven_day": { "utilization": 10.0, "resets_at": "2026-07-02T10:59:59Z" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "limits": [
            { "kind": "session", "group": "session", "percent": 23, "resets_at": "2026-07-02T07:09:59Z", "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 10, "resets_at": "2026-07-02T10:59:59Z", "scope": null },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 17, "resets_at": "2026-07-02T11:00:00Z",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null } }
          ]
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

        let fableQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("fable") }
        #expect(fableQuota != nil)
        #expect(fableQuota?.percentRemaining == 83.0)  // 100 - 17
        #expect(fableQuota?.resetsAt != nil)

        // Unscoped session/weekly entries in the limits array must not create duplicates
        #expect(snapshot.quotas.filter { $0.quotaType == .session }.count == 1)
        #expect(snapshot.quotas.filter { $0.quotaType == .weekly }.count == 1)
    }

    @Test
    func `probe skips malformed limits entries and keeps over-quota negative remaining`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        // Malformed scoped entries (no scope, no model, empty name, no percent) are
        // skipped; duplicate scoped entries yield one quota; a multi-word display
        // name keys on its first word; 105% used stays negative (over-quota signal).
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 50, "resets_at": "2025-01-20T00:00:00Z", "scope": null },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 50, "resets_at": "2025-01-20T00:00:00Z", "scope": { "model": null } },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 50, "resets_at": "2025-01-20T00:00:00Z",
              "scope": { "model": { "id": null, "display_name": "" } } },
            { "kind": "weekly_scoped", "group": "weekly", "resets_at": "2025-01-20T00:00:00Z",
              "scope": { "model": { "id": null, "display_name": "Opus" } } },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 105, "resets_at": "2025-01-20T00:00:00Z",
              "scope": { "model": { "id": null, "display_name": "Fable 5" } } },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 40, "resets_at": "2025-01-20T00:00:00Z",
              "scope": { "model": { "id": null, "display_name": "Fable" } } }
          ]
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

        let fableQuotas = snapshot.quotas.filter { $0.quotaType == .modelSpecific("fable") }
        #expect(fableQuotas.count == 1)
        #expect(fableQuotas.first?.percentRemaining == -5.0)  // 100 - 105, first entry wins

        // Malformed entries produce no quotas: session (legacy) + fable only
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `probe does not duplicate model quota reported in both legacy field and limits array`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futureExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        try createCredentialsFile(at: tempDir, expiresAt: futureExpiry)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day_opus": { "utilization": 60.0, "resets_at": "2025-01-20T00:00:00Z" },
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 60, "resets_at": "2025-01-20T00:00:00Z",
              "scope": { "model": { "id": null, "display_name": "Opus" }, "surface": null } }
          ]
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

        let opusQuotas = snapshot.quotas.filter { $0.quotaType == .modelSpecific("opus") }
        #expect(opusQuotas.count == 1)
        #expect(opusQuotas.first?.percentRemaining == 40.0)  // 100 - 60
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
        #expect(snapshot.costUsage?.kind == .extraUsage)
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
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `probe uses spend when spend and legacy extra usage agree`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 50000, "currency": "USD", "exponent": 2 }
          },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 0,
            "monthly_limit": 50000,
            "decimal_places": 2
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == 0)
        #expect(snapshot.costUsage?.budget == 500)
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `probe prefers spend when legacy extra usage differs`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used": { "amount_minor": 125, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 1000, "currency": "USD", "exponent": 2 }
          },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000,
            "decimal_places": 2
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "1.25"))
        #expect(snapshot.costUsage?.budget == 10)
    }

    @Test
    func `probe rejects negative spend and falls back to legacy extra usage`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used": { "amount_minor": -125, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 1000, "currency": "USD", "exponent": 2 }
          },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000,
            "decimal_places": 2
          }
        }
        """)

        // A negative amount_minor is invalid; the spend row is dropped
        // instead of silently flipping to +$1.25, and legacy takes over.
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20"))
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `probe drops negative legacy credits instead of flipping sign`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": -541,
            "monthly_limit": 2000,
            "decimal_places": 2
          }
        }
        """)

        #expect(snapshot.costUsage == nil)
    }

    @Test
    func `probe drops spend with invalid cap instead of reporting uncapped`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used":  { "amount_minor": 541, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": -2000, "currency": "USD", "exponent": 2 }
          }
        }
        """)

        // A present-but-invalid cap must not be reclassified as "no monthly
        // cap"; the whole shape is dropped.
        #expect(snapshot.costUsage == nil)
    }

    @Test
    func `probe falls back to legacy when spend cap is invalid`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used":  { "amount_minor": 125, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 2000, "currency": "USD", "exponent": -1 }
          },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000,
            "decimal_places": 2
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20"))
    }

    @Test
    func `probe drops legacy shape with invalid monthly limit`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": -2000,
            "decimal_places": 2
          }
        }
        """)

        #expect(snapshot.costUsage == nil)
    }

    @Test
    func `probe parses uncapped spend exactly`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used": { "amount_minor": 123456, "currency": "USD", "exponent": 2 },
            "limit": null,
            "percent": 0
          },
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": null,
            "used_credits": 123456,
            "decimal_places": 2,
            "currency": "USD"
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "1234.56"))
        #expect(snapshot.costUsage?.budget == nil)
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `probe respects spend money exponents`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used": { "amount_minor": 12345, "exponent": 3 },
            "limit": { "amount_minor": 2000, "exponent": 1 }
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "12.345"))
        #expect(snapshot.costUsage?.budget == 200)
    }

    @Test
    func `probe falls back to legacy when spend has no used amount`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": true,
            "used": null,
            "limit": { "amount_minor": 1000, "exponent": 2 }
          },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == 20)
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `probe respects legacy extra usage decimal places`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000,
            "decimal_places": 3
          }
        }
        """)

        #expect(snapshot.costUsage?.totalCost == Decimal(string: "0.541"))
        #expect(snapshot.costUsage?.budget == 2)
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `probe omits disabled spend and extra usage`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "spend": {
            "enabled": false,
            "used": { "amount_minor": 541, "exponent": 2 }
          },
          "extra_usage": {
            "is_enabled": false,
            "used_credits": 541,
            "decimal_places": 2
          }
        }
        """)

        #expect(snapshot.costUsage == nil)
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
        #expect(snapshot.costUsage == nil)
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

        await #expect(throws: ProbeError.sessionExpired()) {
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

        await #expect(throws: ProbeError.sessionExpired()) {
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
        await #expect(throws: ProbeError.sessionExpired()) {
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
