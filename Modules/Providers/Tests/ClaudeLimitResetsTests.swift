import DataSources
import Quotas
import Foundation
import Mockable
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one-time limit resets Claude grants an account (Claude Code's
/// `/limit-reset`), counted in API mode as two notes: Fable resets and the
/// rest → docs/providers/claude/design.md#limit-resets.
@Suite
struct ClaudeLimitResetsTests {

    /// `/api/oauth/usage?cedar_ember=1` for a Team account, live 2026-11-18,
    /// cut to the `cedar_ember` block, labels and ids kept, `event_props` left out.
    static let threeGrants = """
    {
      "five_hour": { "utilization": 10.0, "resets_at": "2026-11-18T12:00:00+00:00" },
      "cedar_ember": {
        "eligible": true, "ineligible_reason": null, "at_limit": false, "exhausted": [],
        "grants": [
          { "id": "full-reset-2611", "label": "One full limit reset (November 2026)",
            "resets_total": 1, "resets_left": 1,
            "starts_at": "2026-11-10T21:30:00+00:00", "ends_at": "2026-12-10T22:00:00+00:00",
            "clears": ["five_hour", "seven_day", "seven_day_overage_included"],
            "paused": false, "usable_now": true, "use_requires_limit": false,
            "percent_used": { "five_hour": 10, "seven_day": 87, "seven_day_overage_included": 70 },
            "blocking": [], "arm": null, "type": "full", "unavailable_reason": null, "gives_back_weekly": false },
          { "id": "launch-2610-fable", "label": "New model launch: one Fable reset for Max, Team Premium and Enterprise Premium",
            "resets_total": 1, "resets_left": 1,
            "starts_at": "2026-11-09T18:00:00+00:00", "ends_at": "2027-03-09T07:59:00+00:00",
            "clears": ["five_hour", "seven_day_overage_included"],
            "paused": false, "usable_now": true, "use_requires_limit": false,
            "percent_used": { "five_hour": 10, "seven_day_overage_included": 70, "seven_day": 87 },
            "blocking": [], "arm": null, "type": "full", "unavailable_reason": null, "gives_back_weekly": true },
          { "id": "launch-2610-fable-6mo", "label": "New model launch: one more Fable reset at 6 months' tenure",
            "resets_total": 1, "resets_left": 1,
            "starts_at": "2026-11-09T18:00:00+00:00", "ends_at": "2027-03-09T07:59:00+00:00",
            "clears": ["five_hour", "seven_day_overage_included"],
            "paused": false, "usable_now": true, "use_requires_limit": false,
            "percent_used": { "five_hour": 10, "seven_day_overage_included": 70, "seven_day": 87 },
            "blocking": [], "arm": null, "type": "full", "unavailable_reason": null, "gives_back_weekly": true }
        ],
        "next_grant_id": "full-reset-2611", "weekly_resets_at": "2026-11-18T07:00:00+00:00",
        "cooldown_until": null, "event_props": null, "paused_held": false
      }
    }
    """

    private func usage(_ json: String) async throws -> UsageSnapshot {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        return try await claude.readAPIResponse(json, subscriptionType: "team")
    }

    @Test
    func `should count Fable resets apart from the resets that refill the other limits`() async throws {
        let snapshot = try await usage(Self.threeGrants)

        #expect(snapshot.extensionMetrics == [
            ExtensionMetric(label: "Fable resets", value: "2", unit: "available"),
            ExtensionMetric(label: "Limit resets", value: "1", unit: "available"),
        ])
    }

    @Test
    func `should show none of a kind the account holds none of`() async throws {
        let snapshot = try await usage("""
        { "five_hour": { "utilization": 10.0 },
          "cedar_ember": { "eligible": true, "grants": [
            { "id": "launch-2610-fable", "resets_left": 0, "type": "full", "gives_back_weekly": true } ] } }
        """)

        #expect(snapshot.extensionMetrics == [
            ExtensionMetric(label: "Fable resets", value: "0", unit: "available"),
            ExtensionMetric(label: "Limit resets", value: "0", unit: "available"),
        ])
    }

    @Test(arguments: [
        #"{ "five_hour": { "utilization": 10.0 } }"#,
        #"{ "five_hour": { "utilization": 10.0 }, "cedar_ember": { "eligible": false, "ineligible_reason": "surface", "grants": [] } }"#,
    ])
    func `should show no resets when Claude doesn't offer them to the account`(_ json: String) async throws {
        let snapshot = try await usage(json)

        #expect(snapshot.extensionMetrics == nil)
        #expect(snapshot.sessionQuota?.percentRemaining == 90)
    }

    @Test
    func `should ask for the resets the way Claude Code does, or Claude answers none`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(subscriptionType: "team")
        let sent = SentRequest()
        given(claude.network).request(.any).willProduce { @Sendable request in
            sent.request = request
            return (Data(Self.threeGrants.utf8), ClaudeHarness.response(200))
        }

        _ = try await claude.fetchUsage(try claude.dataSource("api"))

        let request = try #require(sent.request)
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "cedar_ember", value: "1")))
        #expect(!query.contains { $0.name == "skip_spend" })
        let agent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        #expect(agent.hasPrefix("claude-cli/"))
        #expect(agent.hasSuffix(" (external, cli)"))
    }
}

private final class SentRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?

    var request: URLRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }
}
