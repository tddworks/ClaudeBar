import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct OmpUsageProbeParsingTests {

    /// Representative fixture modeled on real `omp usage --json` output
    /// (omp v16.4.6): three upstream providers, tiered sub-limits, and a
    /// limit without a reset timestamp. All identifiers are synthetic.
    static let sampleResponse = """
    {
      "generatedAt": 1783869272381,
      "reports": [
        {
          "provider": "openai-codex",
          "fetchedAt": 1783869167737,
          "limits": [
            {
              "id": "openai-codex:primary",
              "label": "5 hours",
              "scope": { "provider": "openai-codex", "windowId": "5h", "shared": true },
              "window": { "id": "5h", "label": "5 hours", "durationMs": 18000000, "resetsAt": 1783887168000 },
              "amount": { "used": 0, "limit": 100, "remaining": 100, "usedFraction": 0, "remainingFraction": 1, "unit": "percent" },
              "status": "ok"
            },
            {
              "id": "openai-codex:secondary",
              "label": "7 days",
              "scope": { "provider": "openai-codex", "windowId": "7d", "shared": true },
              "window": { "id": "7d", "label": "7 days", "durationMs": 604800000, "resetsAt": 1784354613000 },
              "amount": { "used": 58, "limit": 100, "remaining": 42, "usedFraction": 0.58, "remainingFraction": 0.42, "unit": "percent" },
              "status": "ok"
            },
            {
              "id": "openai-codex:spark:primary",
              "label": "5 hours (Spark)",
              "scope": { "provider": "openai-codex", "accountId": "0a1b2c3d", "tier": "spark", "windowId": "5h", "shared": true },
              "window": { "id": "5h", "label": "5 hours", "durationMs": 18000000, "resetsAt": 1783887168000 },
              "amount": { "used": 0, "limit": 100, "remaining": 100, "usedFraction": 0, "remainingFraction": 1, "unit": "percent" },
              "status": "ok"
            }
          ],
          "metadata": { "planType": "pro", "email": "codex@example.com", "accountId": "0a1b2c3d-0000-4000-8000-000000000000" }
        },
        {
          "provider": "anthropic",
          "fetchedAt": 1783869231026,
          "limits": [
            {
              "id": "anthropic:5h",
              "label": "Claude 5 Hour",
              "scope": { "provider": "anthropic", "windowId": "5h", "shared": true },
              "window": { "id": "5h", "label": "5 Hour", "durationMs": 18000000, "resetsAt": 1783885200000 },
              "amount": { "used": 8, "limit": 100, "remaining": 92, "usedFraction": 0.08, "remainingFraction": 0.92, "unit": "percent" },
              "status": "ok"
            },
            {
              "id": "anthropic:7d:fable",
              "label": "Claude 7 Day (Fable)",
              "scope": { "provider": "anthropic", "windowId": "7d", "tier": "fable" },
              "window": { "id": "7d", "label": "7 Day", "durationMs": 604800000, "resetsAt": 1784293200000 },
              "amount": { "used": 1, "limit": 100, "remaining": 99, "usedFraction": 0.01, "remainingFraction": 0.99, "unit": "percent" },
              "status": "ok"
            }
          ],
          "metadata": { "email": "claude@example.com", "accountId": "f0e1d2c3" }
        },
        {
          "provider": "zai",
          "fetchedAt": 1783869272092,
          "limits": [
            {
              "id": "zai:tokens:5h",
              "label": "ZAI 5 Hours Token Quota",
              "scope": { "provider": "zai", "windowId": "5h", "shared": true },
              "window": { "id": "5h", "label": "5 Hours", "durationMs": 18000000 },
              "amount": { "usedFraction": 0.25, "remainingFraction": 0.75, "unit": "tokens" },
              "status": "ok"
            },
            {
              "id": "zai:requests:1mo",
              "label": "ZAI Web Search Quota",
              "scope": { "provider": "zai", "windowId": "1mo", "shared": true },
              "window": { "id": "1mo", "label": "Monthly", "durationMs": 2592000000, "resetsAt": 1784388827991 },
              "amount": { "used": 43, "limit": 1000, "remaining": 957, "usedFraction": 0.04, "remainingFraction": 0.96, "unit": "requests" },
              "status": "ok"
            }
          ],
          "metadata": { "endpoint": "https://api.z.ai" }
        }
      ],
      "accountsWithoutUsage": []
    }
    """

    // MARK: - Quota Mapping

    @Test
    func `parses every limit into a quota`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)

        #expect(snapshot.providerId == "omp")
        #expect(snapshot.quotas.count == 7)
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "omp" })
    }

    @Test
    func `maps remaining fraction to percent remaining`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)

        #expect(snapshot.quota(for: .timeLimit("Claude 5h"))?.percentRemaining == 92.0)
        #expect(snapshot.quota(for: .timeLimit("Codex 7d"))?.percentRemaining == 42.0)
        // Fraction-only amounts (no used/limit pair) still map
        #expect(snapshot.quota(for: .timeLimit("Z.ai 5h"))?.percentRemaining == 75.0)
    }

    @Test
    func `labels quotas with provider tier and window`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.contains("Claude 5h"))
        #expect(labels.contains("Claude Fable 7d"))
        #expect(labels.contains("Codex Spark 5h"))
        #expect(labels.contains("Z.ai 1mo"))
    }

    @Test
    func `parses reset time from epoch milliseconds`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)
        let claude = try #require(snapshot.quota(for: .timeLimit("Claude 5h")))

        #expect(claude.resetsAt == Date(timeIntervalSince1970: 1_783_885_200))
    }

    @Test
    func `passes window duration through for pace math`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)

        #expect(snapshot.quota(for: .timeLimit("Claude 5h"))?.windowDuration == 18_000)
        #expect(snapshot.quota(for: .timeLimit("Codex 7d"))?.windowDuration == 604_800)
    }

    @Test
    func `limit without reset timestamp keeps nil resetsAt`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)
        let zai = try #require(snapshot.quota(for: .timeLimit("Z.ai 5h")))

        #expect(zai.resetsAt == nil)
    }

    // MARK: - Account Email

    @Test
    func `email is nil when accounts span multiple emails`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)

        #expect(snapshot.accountEmail == nil)
    }

    @Test
    func `extracts email for a single account`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h", "durationMs": 18000000 },
              "amount": { "usedFraction": 0.5, "remainingFraction": 0.5 }
            } ],
            "metadata": { "email": "solo@example.com" }
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.accountEmail == "solo@example.com")
    }

    // MARK: - Multiple Accounts on One Provider

    @Test
    func `discriminates duplicate accounts on the same provider`() throws {
        let json = """
        { "reports": [
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h", "durationMs": 18000000 },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "email": "work@example.com" }
          },
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h", "durationMs": 18000000 },
              "amount": { "remainingFraction": 0.4 }
            } ],
            "metadata": { "email": "home@example.com" }
          }
        ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.contains("Claude 5h · work"))
        #expect(labels.contains("Claude 5h · home"))
        // Quota keys are persisted and used as stable UI identifiers —
        // they must never collide across accounts.
        let keys = Set(snapshot.quotas.map(\.quotaType.quotaKey))
        #expect(keys.count == snapshot.quotas.count)
    }

    @Test
    func `qualifies multiple meters sharing one window`() throws {
        // Z.ai can meter tokens and requests over the same window; both
        // must stay distinguishable without degrading to bare ordinals.
        let json = """
        { "reports": [ {
            "provider": "zai",
            "limits": [
              {
                "id": "zai:tokens:5h",
                "scope": { "windowId": "5h" },
                "window": { "id": "5h", "durationMs": 18000000 },
                "amount": { "usedFraction": 0.2, "remainingFraction": 0.8, "unit": "tokens" }
              },
              {
                "id": "zai:requests:5h",
                "scope": { "windowId": "5h" },
                "window": { "id": "5h", "durationMs": 18000000 },
                "amount": { "usedFraction": 0.1, "remainingFraction": 0.9, "unit": "requests" }
              }
            ]
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.contains("Z.ai Tokens 5h"))
        #expect(labels.contains("Z.ai Requests 5h"))
        #expect(!labels.contains { $0.hasSuffix("(2)") })
    }

    // MARK: - Accounts Without Usage

    @Test
    func `empty accountsWithoutUsage adds no metric rows`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)

        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `mixed pool keeps quotas and lists unreported accounts`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h", "durationMs": 18000000 },
              "amount": { "remainingFraction": 0.9 }
            } ]
        } ],
          "accountsWithoutUsage": [
            { "provider": "github-copilot", "type": "oauth", "email": "work@example.com" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 1)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.count == 1)
        #expect(metrics[0].label == "Copilot · work@example.com")
        #expect(metrics[0].value == "No usage reported")
    }

    @Test
    func `all-unreported pool yields account rows instead of noData`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "solo@example.com" },
            { "provider": "openai-codex", "type": "api_key" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.isEmpty)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Claude · solo@example.com", "Codex · API key"])
        #expect(metrics.allSatisfy { $0.value == "No usage reported" })
    }

    @Test
    func `anonymous accounts on one provider get unique row labels`() throws {
        // MenuContentView keys these cards by label — collisions would
        // hide or reuse rows.
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "openai-codex", "type": "api_key" },
            { "provider": "openai-codex", "type": "api_key" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let labels = try #require(snapshot.extensionMetrics).map(\.label)

        #expect(labels == ["Codex · API key", "Codex · API key (2)"])
        #expect(Set(labels).count == labels.count)
    }

    @Test
    func `single unreported account contributes the snapshot email`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "solo@example.com" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.accountEmail == "solo@example.com")
    }

    // MARK: - Reports Without Usable Limits

    @Test
    func `report with zero limits still lists its account`() throws {
        // Ollama's usage provider deliberately reports `limits: []` (no
        // standalone quota API); a report exists, so the account never
        // appears in accountsWithoutUsage — it must not vanish here.
        let json = """
        { "reports": [
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h", "durationMs": 18000000 },
              "amount": { "remainingFraction": 0.9 }
            } ]
          },
          {
            "provider": "ollama",
            "limits": [],
            "notes": ["Ollama does not expose a standalone quota usage API; per-response token usage is reported during requests."],
            "metadata": { "email": "local@ollama.dev" }
          }
        ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 1)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Ollama · local@ollama.dev"])
        #expect(metrics[0].value == "No usage reported")
    }

    @Test
    func `pool with only zero-limit reports yields rows instead of noData`() throws {
        let json = """
        { "reports": [ { "provider": "ollama", "limits": [] } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.extensionMetrics?.map(\.label) == ["Ollama · account 1"])
    }

    @Test
    func `report identity falls back to limit scope`() throws {
        // Gemini/Kimi-style reports carry identity in limit scopes rather
        // than metadata; a report whose limits are all unusable must still
        // be attributed via that scope.
        let json = """
        { "reports": [ {
            "provider": "google-gemini-cli",
            "limits": [ {
              "scope": { "windowId": "1d", "projectId": "my-gcp-project" },
              "window": { "id": "1d" }
            } ]
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Gemini · my-gcp-project"])
    }

    @Test
    func `anonymous zero-limit reports on one provider stay distinct`() throws {
        let json = """
        { "reports": [
            { "provider": "ollama", "limits": [] },
            { "provider": "ollama", "limits": [] }
        ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let labels = try #require(snapshot.extensionMetrics).map(\.label)

        #expect(labels == ["Ollama · #1", "Ollama · #2"])
        #expect(Set(labels).count == labels.count)
    }

    // MARK: - Upstream Display Names

    @Test(arguments: [
        // Every id omp v16.4.6's usage registry emits (@oh-my-pi/pi-ai/src/usage/*).
        ("anthropic", "Claude"),
        ("openai-codex", "Codex"),
        ("zai", "Z.ai"),
        ("google-gemini-cli", "Gemini"),
        ("google-antigravity", "Antigravity"),
        ("github-copilot", "Copilot"),
        ("kimi-code", "Kimi"),
        ("minimax-code", "MiniMax"),
        ("minimax-code-cn", "MiniMax CN"),
        ("opencode-go", "OpenCode Go"),
        ("ollama", "Ollama"),
        ("ollama-cloud", "Ollama Cloud"),
    ])
    func `maps emitted provider ids to display names`(id: String, expected: String) {
        #expect(OmpUsageProbe.upstreamDisplayName(id) == expected)
    }

    // MARK: - Robustness

    @Test
    func `tolerates noise around the JSON object`() throws {
        let noisy = "Synced 3 accounts\n\(Self.sampleResponse)\nDone."
        let snapshot = try OmpUsageProbe.parse(noisy)

        #expect(snapshot.quotas.count == 7)
    }

    @Test
    func `skips limits without usable amounts`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [
              {
                "scope": { "windowId": "5h" },
                "window": { "id": "5h" },
                "amount": { "remainingFraction": 0.9 }
              },
              {
                "scope": { "windowId": "7d" },
                "window": { "id": "7d" }
              }
            ]
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 1)
    }

    @Test
    func `throws parseFailed on malformed output`() {
        #expect(throws: ProbeError.self) {
            try OmpUsageProbe.parse("not json at all")
        }
        #expect(throws: ProbeError.self) {
            try OmpUsageProbe.parse("{ \"reports\": [ { } ] }")
        }
    }

    @Test
    func `throws noData when no accounts are authenticated`() {
        #expect(throws: ProbeError.noData) {
            try OmpUsageProbe.parse("{ \"reports\": [] }")
        }
    }
}
