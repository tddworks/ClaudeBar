import DataSources
import Quotas
import Foundation
import Mockable
import Testing

/// `claude.json`'s `api` data source — the key lookup, the OAuth refresh, the
/// usage request and its JSON mapping — over stubbed connections.
/// Ported from `ClaudeAPIUsageProbeTests`.
@Suite
struct ClaudeAPITests {

    // MARK: - Helpers

    /// A usage body read with a valid credentials file whose plan is `subscriptionType`.
    private func usage(_ json: String, subscriptionType: String? = "claude_pro") async throws -> UsageSnapshot {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        return try await claude.readAPIResponse(json, subscriptionType: subscriptionType)
    }

    /// The `UsageError` a fetch threw, or `nil` when it succeeded.
    private func failure(of source: DataSource, in claude: ClaudeHarness) async -> UsageError? {
        do {
            _ = try await claude.fetchUsage(source)
            return nil
        } catch let error as UsageError {
            return error
        } catch {
            Issue.record("Unexpected error \(error)")
            return nil
        }
    }

    // MARK: - Availability

    @Test
    func `the api is available when a credentials file exists`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()

        let source = try claude.dataSource("api")

        #expect(source.hasKey == true)
        #expect(await source.isReady() == true)
    }

    @Test
    func `the api is not available when no credentials exist`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        let source = try claude.dataSource("api")

        #expect(source.hasKey == false)
        #expect(await source.isReady() == false)
    }

    // MARK: - Snapshot cache (TTL)

    @Test
    func `a fetch within the cache ttl is served from the cache`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(subscriptionType: "claude_max")
        let first = """
        {
          "five_hour": { "utilization": 25.0, "resets_at": "2025-01-15T10:00:00Z" }
        }
        """
        // Any request after the first would read 50% used.
        let later = #"{ "five_hour": { "utilization": 50.0 } }"#
        let calls = Counter()
        given(claude.network).request(.any).willProduce { @Sendable _ in
            (Data((calls.next() == 1 ? first : later).utf8), ClaudeHarness.response(200))
        }
        let source = try claude.dataSource("api")

        let one = try await claude.fetchUsage(source)
        let two = try await claude.fetchUsage(source)
        let three = try await claude.fetchUsage(source)

        #expect(one.quotas.first?.percentRemaining == 75.0)
        #expect(two.quotas.first?.percentRemaining == 75.0)
        #expect(three.quotas.first?.percentRemaining == 75.0)
    }

    // MARK: - Rate limit (HTTP 429)

    @Test
    func `a 429 with Retry-After seconds is rate limited until then`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        given(claude.network).request(.any).willReturn((Data(), ClaudeHarness.response(429, ["Retry-After": "120"])))

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        #expect(error == .rateLimited(retryAt: claude.now.addingTimeInterval(120)))
    }

    @Test
    func `a 429 without Retry-After waits five minutes`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        given(claude.network).request(.any).willReturn((Data(), ClaudeHarness.response(429)))

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        #expect(error == .rateLimited(retryAt: claude.now.addingTimeInterval(300)))
    }

    @Test
    func `a fetch during the rate limit window is refused without asking again`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        // The first request is throttled; any later one would succeed.
        let calls = Counter()
        given(claude.network).request(.any).willProduce { @Sendable _ in
            calls.next() == 1
                ? (Data(), ClaudeHarness.response(429, ["Retry-After": "600"]))
                : (Data(#"{ "five_hour": { "utilization": 10.0 } }"#.utf8), ClaudeHarness.response(200))
        }
        let source = try claude.dataSource("api")

        _ = await failure(of: source, in: claude)
        let second = await failure(of: source, in: claude)

        #expect(second == .rateLimited(retryAt: claude.now.addingTimeInterval(600)))
    }

    // MARK: - Authentication

    @Test
    func `no credentials means authentication is required`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        #expect(error == .authenticationRequired)
    }

    // MARK: - Response parsing

    @Test
    func `session usage is read from five_hour`() async throws {
        let snapshot = try await usage("""
        {
          "five_hour": {
            "utilization": 25.5,
            "resets_at": "2025-01-15T10:00:00Z"
          }
        }
        """, subscriptionType: "claude_max")

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.accountTier == .claudeMax)
        let session = snapshot.quotas.first { $0.quotaType == .session }
        #expect(session?.percentRemaining == 74.5)  // 100 - 25.5
        #expect(session?.resetsAt != nil)
    }

    @Test
    func `the reset countdown is written in hours, never days`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.now = Date(timeIntervalSince1970: 1_750_000_000)
        let resetsAt = ISO8601DateFormatter().string(from: claude.now.addingTimeInterval(50 * 3600 + 3 * 60))
        let past = ISO8601DateFormatter().string(from: claude.now.addingTimeInterval(-60))

        let snapshot = try await claude.readAPIResponse("""
        {
          "five_hour": { "utilization": 10, "resets_at": "\(past)" },
          "seven_day": { "utilization": 10, "resets_at": "\(resetsAt)" }
        }
        """)

        #expect(snapshot.quota(for: .weekly)?.resetText == "Resets in 50h 3m")
        #expect(snapshot.quota(for: .session)?.resetText == nil)
    }

    @Test
    func `weekly usage is read from seven_day`() async throws {
        let snapshot = try await usage("""
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day": { "utilization": 45.0, "resets_at": "2025-01-20T00:00:00Z" }
        }
        """, subscriptionType: nil)

        let weekly = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weekly?.percentRemaining == 55.0)  // 100 - 45
    }

    @Test
    func `model quotas are read from seven_day_sonnet and seven_day_opus`() async throws {
        let snapshot = try await usage("""
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day_sonnet": { "utilization": 30.0, "resets_at": "2025-01-20T00:00:00Z" },
          "seven_day_opus": { "utilization": 60.0, "resets_at": "2025-01-20T00:00:00Z" }
        }
        """, subscriptionType: nil)

        #expect(snapshot.quota(for: .modelSpecific("sonnet"))?.percentRemaining == 70.0)  // 100 - 30
        #expect(snapshot.quota(for: .modelSpecific("opus"))?.percentRemaining == 40.0)  // 100 - 60
    }

    @Test
    func `a fable quota is read from the scoped limits array`() async throws {
        // Newer API responses report model limits via a generic "limits" array
        // (kind "weekly_scoped" + scope.model.display_name) instead of
        // dedicated seven_day_<model> fields.
        let snapshot = try await usage("""
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
        """, subscriptionType: nil)

        let fable = snapshot.quota(for: .modelSpecific("fable"))
        #expect(fable?.percentRemaining == 83.0)  // 100 - 17
        #expect(fable?.resetsAt != nil)
        // Unscoped session/weekly entries in the limits array must not create duplicates
        #expect(snapshot.quotas.filter { $0.quotaType == .session }.count == 1)
        #expect(snapshot.quotas.filter { $0.quotaType == .weekly }.count == 1)
    }

    @Test
    func `malformed limits entries are skipped and over-quota stays negative`() async throws {
        // Malformed scoped entries (no scope, no model, empty name, no percent) are
        // skipped; duplicate scoped entries yield one quota; a multi-word display
        // name keys on its first word; 105% used stays negative (over-quota signal).
        let snapshot = try await usage("""
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
        """, subscriptionType: nil)

        let fable = snapshot.quotas.filter { $0.quotaType == .modelSpecific("fable") }
        #expect(fable.count == 1)
        #expect(fable.first?.percentRemaining == -5.0)  // 100 - 105, first entry wins
        // Malformed entries produce no quotas: session (legacy) + fable only
        #expect(snapshot.quotas.count == 2)
    }

    @Test
    func `a model in both the legacy field and the limits array is not duplicated`() async throws {
        let snapshot = try await usage("""
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day_opus": { "utilization": 60.0, "resets_at": "2025-01-20T00:00:00Z" },
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 60, "resets_at": "2025-01-20T00:00:00Z",
              "scope": { "model": { "id": null, "display_name": "Opus" }, "surface": null } }
          ]
        }
        """, subscriptionType: nil)

        let opus = snapshot.quotas.filter { $0.quotaType == .modelSpecific("opus") }
        #expect(opus.count == 1)
        #expect(opus.first?.percentRemaining == 40.0)  // 100 - 60
    }

    // MARK: - Money

    @Test
    func `extra usage credits are cents converted to dollars`() async throws {
        // API returns used_credits and monthly_limit in cents
        let snapshot = try await usage("""
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 541,
            "monthly_limit": 2000
          }
        }
        """, subscriptionType: "claude_pro")

        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))  // 541 cents
        #expect(snapshot.costUsage?.budget == Decimal(string: "20"))  // 2000 cents
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `large extra usage amounts are cents converted to dollars`() async throws {
        // Simulates the real scenario: $26.72 spent of $50 budget
        // API returns 2672 cents and 5000 cents
        let snapshot = try await usage("""
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2025-01-15T10:00:00Z" },
          "extra_usage": {
            "is_enabled": true,
            "used_credits": 2672,
            "monthly_limit": 5000
          }
        }
        """, subscriptionType: "claude_pro")

        // 2672 cents -> $26.72 (NOT $2672.00)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "26.72"))
        // 5000 cents -> $50.00 (NOT $5000.00)
        #expect(snapshot.costUsage?.budget == Decimal(string: "50"))
        #expect(snapshot.costUsage?.formattedCost.contains("26.72") == true)
        #expect(snapshot.costUsage?.kind == .extraUsage)
    }

    @Test
    func `spend is used when spend and legacy extra usage agree`() async throws {
        let snapshot = try await usage("""
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
    func `spend is preferred when legacy extra usage differs`() async throws {
        let snapshot = try await usage("""
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
    func `negative spend is rejected and legacy extra usage takes over`() async throws {
        let snapshot = try await usage("""
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
    func `negative legacy credits are dropped instead of flipping sign`() async throws {
        let snapshot = try await usage("""
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
    func `spend with an invalid cap is dropped instead of reported uncapped`() async throws {
        let snapshot = try await usage("""
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
    func `legacy extra usage takes over when the spend cap is invalid`() async throws {
        let snapshot = try await usage("""
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
    func `legacy extra usage with an invalid monthly limit is dropped`() async throws {
        let snapshot = try await usage("""
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
    func `uncapped spend is read exactly`() async throws {
        let snapshot = try await usage("""
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
    func `spend money exponents are respected`() async throws {
        let snapshot = try await usage("""
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
    func `legacy extra usage takes over when spend has no used amount`() async throws {
        let snapshot = try await usage("""
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
    func `legacy extra usage decimal places are respected`() async throws {
        let snapshot = try await usage("""
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
    func `disabled spend and extra usage are omitted`() async throws {
        let snapshot = try await usage("""
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
    func `an empty response still shows the plan badge`() async throws {
        let snapshot = try await usage("{}", subscriptionType: "claude_max")

        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.costUsage == nil)
        #expect(snapshot.accountTier == .claudeMax)
    }

    // MARK: - Account tier

    @Test
    func `claude_max is the Max plan`() async throws {
        let snapshot = try await usage("""
        { "five_hour": { "utilization": 10.0 } }
        """, subscriptionType: "claude_max")

        #expect(snapshot.accountTier == .claudeMax)
    }

    @Test
    func `claude_pro is the Pro plan`() async throws {
        let snapshot = try await usage("""
        { "five_hour": { "utilization": 10.0 } }
        """, subscriptionType: "claude_pro")

        #expect(snapshot.accountTier == .claudePro)
    }

    // MARK: - Errors

    @Test
    func `a 401 the refresh cannot fix means the session expired`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        // The usage request and the refresh both answer 401.
        given(claude.network).request(.any).willReturn((Data(), ClaudeHarness.response(401)))

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        #expect(error == .sessionExpired())
    }

    @Test
    func `a 403 that persists after a refresh means authentication is required`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        given(claude.network).request(.any).willProduce { @Sendable request in
            if request.url?.absoluteString.contains("oauth/token") == true {
                return (Data(#"{ "access_token": "new-token", "expires_in": 3600 }"#.utf8), ClaudeHarness.response(200))
            }
            return (Data(), ClaudeHarness.response(403))
        }

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        #expect(error == .authenticationRequired)
    }

    @Test
    func `a body that is not json fails to parse`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        given(claude.network).request(.any).willReturn((Data("not json".utf8), ClaudeHarness.response(200)))

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        guard case .parseFailed = error else {
            Issue.record("Expected parseFailed, got \(String(describing: error))")
            return
        }
    }

    @Test
    func `a network error is an execution failure`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials()
        given(claude.network).request(.any).willThrow(URLError(.notConnectedToInternet))

        let error = await failure(of: try claude.dataSource("api"), in: claude)

        guard case .executionFailed = error else {
            Issue.record("Expected executionFailed, got \(String(describing: error))")
            return
        }
    }
}

// MARK: - Token refresh

@Suite
struct ClaudeAPITokenRefreshTests {

    private static let usageOK = #"{ "five_hour": { "utilization": 10.0 } }"#

    private static func isTokenRequest(_ request: URLRequest) -> Bool {
        request.url?.absoluteString.contains("oauth/token") == true
    }

    private static func bearer(_ request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization")
    }

    /// Writes `~/.claude/.credentials.json` from inside a `@Sendable` stub.
    private static func writeCredentials(in home: URL, accessToken: String, refreshToken: String, expiresAt: Double) {
        let oauth: [String: Any] = ["accessToken": accessToken, "refreshToken": refreshToken, "expiresAt": expiresAt]
        try? JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
            .write(to: home.appendingPathComponent(".claude/.credentials.json"))
    }

    @Test
    func `an expired token is refreshed, used and written back`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        // Token expired 1 hour ago
        let pastExpiry = claude.now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try claude.writeCredentials(accessToken: "old-token", expiresAt: pastExpiry, subscriptionType: "claude_max")
        let refreshResponse = """
        {
          "access_token": "new-token",
          "refresh_token": "new-refresh-token",
          "expires_in": 3600
        }
        """
        let usageResponse = """
        { "five_hour": { "utilization": 10.0 } }
        """
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                return (Data(refreshResponse.utf8), ClaudeHarness.response(200))
            }
            // Only the refreshed token gets usage.
            guard Self.bearer(request) == "Bearer new-token" else { return (Data(), ClaudeHarness.response(500)) }
            return (Data(usageResponse.utf8), ClaudeHarness.response(200))
        }

        let snapshot = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.first?.percentRemaining == 90.0)
        let saved = try claude.readCredentials()
        #expect(saved["accessToken"] as? String == "new-token")
        #expect(saved["refreshToken"] as? String == "new-refresh-token")
        #expect(saved["subscriptionType"] as? String == "claude_max")
        // Claude Code reads expiresAt as a number of milliseconds.
        #expect(saved["expiresAt"] is String == false)
        let expected = Double(Int64((claude.now.timeIntervalSince1970 + 3600) * 1000))
        #expect((saved["expiresAt"] as? NSNumber)?.doubleValue == expected)
        // Nothing the CLI does not write is added.
        #expect(saved["refreshedAt"] == nil)
    }

    @Test
    func `a refresh refused with invalid_grant means the session expired`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let pastExpiry = claude.now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try claude.writeCredentials(expiresAt: pastExpiry)
        let errorResponse = """
        { "error": "invalid_grant", "error_description": "Refresh token has been revoked" }
        """
        given(claude.network).request(.any).willReturn((Data(errorResponse.utf8), ClaudeHarness.response(400)))

        do {
            _ = try await claude.fetchUsage(try claude.dataSource("api"))
            Issue.record("Expected sessionExpired")
        } catch let error as UsageError {
            #expect(error == .sessionExpired())
        }
    }

    @Test
    func `the next fetch recovers once the CLI has written new credentials`() async throws {
        // Scenario: the stored refresh token is invalid, but the CLI has
        // re-authenticated and written new credentials to the file.
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let pastExpiry = claude.now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try claude.writeCredentials(accessToken: "old-token", expiresAt: pastExpiry)
        let refreshes = Counter()
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                if refreshes.next() == 1 {
                    // First refresh attempt: old token is invalid
                    let errorResponse = """
                    { "error": "invalid_grant", "error_description": "Refresh token has been revoked" }
                    """
                    return (Data(errorResponse.utf8), ClaudeHarness.response(400))
                }
                // Second refresh attempt (with fresh file credentials): success
                let refreshResponse = """
                { "access_token": "brand-new-token", "refresh_token": "brand-new-refresh", "expires_in": 3600 }
                """
                return (Data(refreshResponse.utf8), ClaudeHarness.response(200))
            }
            let usageResponse = """
            { "five_hour": { "utilization": 15.0 } }
            """
            return (Data(usageResponse.utf8), ClaudeHarness.response(200))
        }
        let source = try claude.dataSource("api")

        do {
            _ = try await claude.fetchUsage(source)
            Issue.record("Expected sessionExpired")
        } catch let error as UsageError {
            #expect(error == .sessionExpired())
        }

        // Simulate CLI re-authentication: write new credentials to file
        let newExpiry = claude.now.addingTimeInterval(-60).timeIntervalSince1970 * 1000
        try claude.writeCredentials(accessToken: "cli-refreshed-token", refreshToken: "cli-refreshed-refresh", expiresAt: newExpiry)

        let snapshot = try await claude.fetchUsage(source)

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.first?.percentRemaining == 85.0)
        #expect(try claude.readCredentials()["accessToken"] as? String == "brand-new-token")
    }

    @Test
    func `a failed refresh uses the token the CLI wrote meanwhile`() async throws {
        // Scenario: during a single fetch, the refresh fails but the CLI has
        // updated the file in the meantime with a different access token.
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let pastExpiry = claude.now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        try claude.writeCredentials(accessToken: "stale-token", expiresAt: pastExpiry)
        let home = claude.home
        let futureExpiry = claude.now.addingTimeInterval(3600).timeIntervalSince1970 * 1000
        let refreshes = Counter()
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                _ = refreshes.next()
                // Simulate the CLI updating the file concurrently
                Self.writeCredentials(in: home, accessToken: "brand-new-token", refreshToken: "brand-new-refresh", expiresAt: futureExpiry)
                let errorResponse = """
                { "error": "invalid_grant", "error_description": "Token revoked" }
                """
                return (Data(errorResponse.utf8), ClaudeHarness.response(400))
            }
            guard Self.bearer(request) == "Bearer brand-new-token" else { return (Data(), ClaudeHarness.response(500)) }
            let usageResponse = """
            { "five_hour": { "utilization": 20.0 } }
            """
            return (Data(usageResponse.utf8), ClaudeHarness.response(200))
        }

        let snapshot = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.first?.percentRemaining == 80.0)  // 100 - 20
        #expect(refreshes.next() == 2)  // only one refresh attempt was made before this
    }
}

// MARK: - Setup token (environment)

@Suite
struct ClaudeAPISetupTokenTests {

    private static func isTokenRequest(_ request: URLRequest) -> Bool {
        request.url?.absoluteString.contains("oauth/token") == true
    }

    @Test
    func `a setup token is used without a refresh`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "setup-token-abc123"]
        let usageResponse = """
        {
          "five_hour": { "utilization": 20.0, "resets_at": "2025-01-15T10:00:00Z" },
          "seven_day": { "utilization": 40.0, "resets_at": "2025-01-20T00:00:00Z" }
        }
        """
        // A refresh, were one tried, would expire the session.
        given(claude.network).request(.any).willProduce { @Sendable request in
            Self.isTokenRequest(request)
                ? (Data(#"{"error":"invalid_grant"}"#.utf8), ClaudeHarness.response(400))
                : (Data(usageResponse.utf8), ClaudeHarness.response(200))
        }

        let snapshot = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas.first { $0.quotaType == .session }?.percentRemaining == 80.0)  // 100 - 20
        #expect(snapshot.quotas.first { $0.quotaType == .weekly }?.percentRemaining == 60.0)  // 100 - 40
    }

    @Test
    func `a setup token's trailing newline is trimmed before the Authorization header`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "setup-token-abc123\n"]
        let usageResponse = """
        {
          "five_hour": { "utilization": 20.0, "resets_at": "2025-01-15T10:00:00Z" }
        }
        """
        given(claude.network).request(.any).willProduce { @Sendable request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer setup-token-abc123"
                ? (Data(usageResponse.utf8), ClaudeHarness.response(200))
                : (Data(), ClaudeHarness.response(500))
        }

        let snapshot = try await claude.fetchUsage(try claude.dataSource("api"))

        #expect(snapshot.quotas.first?.percentRemaining == 80.0)
    }

    @Test
    func `a setup token answered with 401 needs authentication, with no refresh`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "expired-setup-token"]
        // A refresh, were one possible, would hand out a working token.
        given(claude.network).request(.any).willProduce { @Sendable request in
            if Self.isTokenRequest(request) {
                return (Data(#"{ "access_token": "new-token", "expires_in": 3600 }"#.utf8), ClaudeHarness.response(200))
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token"
                ? (Data(#"{ "five_hour": { "utilization": 10.0 } }"#.utf8), ClaudeHarness.response(200))
                : (Data(), ClaudeHarness.response(401))
        }

        do {
            _ = try await claude.fetchUsage(try claude.dataSource("api"))
            Issue.record("Expected authenticationRequired")
        } catch let error as UsageError {
            #expect(error == .authenticationRequired)
        }
    }

    @Test
    func `the api is available with a setup token in the environment`() async throws {
        var claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        claude.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "my-setup-token"]

        let source = try claude.dataSource("api")

        #expect(source.hasKey == true)
        #expect(await source.isReady() == true)
    }
}
