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

    // MARK: - Monetary Limits

    @Test
    func `maps capped zero spend to a monetary quota`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "id": "anthropic:extra",
              "label": "Claude Extra Usage",
              "scope": { "provider": "anthropic", "windowId": "extra" },
              "amount": {
                "used": 0,
                "limit": 500,
                "remaining": 500,
                "usedFraction": 0,
                "remainingFraction": 1,
                "unit": "usd"
              }
            } ]
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Claude Extra")))

        #expect(quota.percentRemaining == 100)
        #expect(quota.dollarUsed == 0)
        #expect(quota.dollarCap == 500)
        #expect(quota.compactTitle == "Extra")
        #expect(quota.group == "Claude")
    }

    @Test
    func `capped spend honors fractions and preserves rounded dollars`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "extra" },
              "amount": {
                "used": 123.45,
                "limit": 500,
                "remainingFraction": 0.8,
                "usedFraction": 0.2,
                "unit": "USD"
              }
            } ]
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Claude Extra")))

        #expect(quota.percentRemaining == 80)
        #expect(quota.dollarUsed == Decimal(string: "123.45"))
        #expect(quota.dollarCap == 500)
    }

    @Test
    func `monetary decode keeps cent-boundary values exact`() throws {
        // Decimal decodes straight from the JSON number token: 1.005 rounds
        // to $1.01. A Double round-trip would decode 1.00499… and show $1.00.
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "extra" },
              "amount": { "used": 1.005, "limit": 1.25e1, "unit": "usd" }
            } ]
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Claude Extra")))

        #expect(quota.dollarUsed == Decimal(string: "1.01"))
        #expect(quota.dollarCap == Decimal(string: "12.5"))
        // Derived percent math (no explicit fractions): (12.5-1.005)/12.5.
        let percent = try #require(quota.percentRemaining)
        #expect(abs(percent - 91.96) < 0.0001)
    }

    @Test
    func `monetary label falls back to window id`() throws {
        let json = """
        { "reports": [ {
            "provider": "opencode-go",
            "limits": [ {
              "window": { "id": "monthly" },
              "amount": { "used": 50, "limit": 500, "unit": "usd" }
            } ]
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("OpenCode Go Monthly")))

        #expect(quota.compactTitle == "Monthly")
    }

    @Test
    func `uncapped spend becomes a grouped note instead of a quota`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "id": "anthropic:extra",
              "label": "Claude Extra Usage",
              "scope": { "provider": "anthropic", "windowId": "extra" },
              "amount": { "used": 1234.56, "unit": "usd" }
            } ],
            "metadata": { "email": "solo@example.com" }
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.isEmpty)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.count == 1)
        #expect(metrics[0].label == "Claude Extra Usage")
        #expect(metrics[0].value == "Extra usage $1,234.56 spent · no cap")
        #expect(metrics[0].icon == "dollarsign.circle")
        #expect(metrics[0].group == "Claude")
        #expect(snapshot.quotaGroups.first?.note == "Extra usage $1,234.56 spent · no cap")
    }

    @Test
    func `windowless cursor spend labels suppress the usd meter`() throws {
        let json = """
        { "reports": [ {
            "provider": "cursor",
            "limits": [
              {
                "id": "cursor:usd:included",
                "label": "included spend",
                "amount": { "used": 1234.56, "limit": 5000, "unit": "UsD" }
              },
              {
                "id": "cursor:usd:bonus",
                "label": "bonus spend",
                "amount": { "used": 10, "limit": 100, "unit": "usd" }
              }
            ]
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels == ["Cursor Spend", "Cursor Spend (2)"])
        #expect(labels.allSatisfy { !$0.localizedCaseInsensitiveContains("usd") })
        #expect(snapshot.quotas.first?.compactTitle == "Spend")
        #expect(snapshot.quotas.first?.dollarUsed == Decimal(string: "1234.56"))
        #expect(snapshot.quotas.first?.dollarCap == 5000)
    }

    @Test
    func `monetary and window quotas share the account group`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [
              {
                "scope": { "windowId": "5h" },
                "window": { "id": "5h", "durationMs": 18000000 },
                "amount": { "remainingFraction": 0.9, "unit": "percent" }
              },
              {
                "scope": { "windowId": "extra" },
                "amount": { "used": 125, "limit": 500, "unit": "usd" }
              }
            ]
        } ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.map(\.quotaType.displayName) == ["Claude 5h", "Claude Extra"])
        #expect(snapshot.quotas.allSatisfy { $0.group == "Claude" })
        #expect(snapshot.quotaGroups.count == 1)
        #expect(snapshot.quotaGroups[0].quotas.count == 2)
    }

    @Test
    func `uncapped spend notes discriminate same-provider accounts`() throws {
        let json = """
        { "reports": [
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "extra" },
              "amount": { "used": 10, "unit": "usd" }
            } ],
            "metadata": { "email": "work@example.com" }
          },
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "extra" },
              "amount": { "used": 20, "unit": "usd" }
            } ],
            "metadata": { "email": "home@example.com" }
          }
        ] }
        """

        let snapshot = try OmpUsageProbe.parse(json)
        let metrics = try #require(snapshot.extensionMetrics)

        #expect(snapshot.quotas.isEmpty)
        #expect(metrics.map(\.label) == [
            "Claude Extra Usage · work",
            "Claude Extra Usage · home",
        ])
        #expect(metrics.map(\.group) == ["Claude · work", "Claude · home"])
        #expect(Set(metrics.map(\.label)).count == metrics.count)
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

    // MARK: - Card Title Humanization

    /// Modeled on live `omp usage --json` output for `kimi-code` (omp
    /// v17.0.2): the reporter emits machine window ids alongside human
    /// labels. All values are synthetic.
    static let kimiResponse = """
    { "reports": [ {
        "provider": "kimi-code",
        "limits": [
          {
            "id": "kimi-code:0",
            "label": "Total quota",
            "scope": { "provider": "kimi-code", "windowId": "default", "shared": true },
            "window": { "id": "default", "label": "Usage window", "resetsAt": 1784828755000 },
            "amount": { "unit": "unknown", "limit": 100, "used": 16, "remaining": 84, "usedFraction": 0.16, "remainingFraction": 0.84 }
          },
          {
            "id": "kimi-code:1",
            "label": "5h limit",
            "scope": { "provider": "kimi-code", "windowId": "300time_unit_minute", "shared": true },
            "window": { "id": "300time_unit_minute", "label": "5h limit", "durationMs": 18000000 },
            "amount": { "unit": "unknown", "limit": 100, "used": 81, "remaining": 19, "usedFraction": 0.81, "remainingFraction": 0.19 }
          }
        ],
        "metadata": { "endpoint": "https://api.kimi.com/coding/v1/usages" }
    } ] }
    """

    @Test
    func `derives a compact card title from the window duration for machine ids`() throws {
        // "300time_unit_minute" is omp's machine id for Kimi's 5-hour rate
        // limit; the card must read "5h", not the raw id. The quota label —
        // and therefore the persisted quota key — keeps the raw token.
        let snapshot = try OmpUsageProbe.parse(Self.kimiResponse)
        let rate = try #require(snapshot.quota(for: .timeLimit("Kimi 300time_unit_minute")))

        #expect(rate.compactTitle == "5h")
        #expect(rate.percentRemaining == 19.0)
        #expect(rate.windowDuration == 18_000)
    }

    @Test
    func `falls back to the limit label for card titles when a window has no duration`() throws {
        // Kimi's summary row has windowId "default" and no duration; the
        // card shows Kimi's own "Total quota" label while the quota key
        // stays on the raw token.
        let snapshot = try OmpUsageProbe.parse(Self.kimiResponse)
        let total = try #require(snapshot.quota(for: .timeLimit("Kimi default")))

        #expect(total.compactTitle == "Total quota")
        #expect(total.resetsAt == Date(timeIntervalSince1970: 1_784_828_755))
        #expect(snapshot.quotas.allSatisfy { $0.group == "Kimi" })
    }

    @Test
    func `strips the provider prefix from label-derived card titles`() throws {
        // Gemini limit labels embed the provider name ("Gemini <model>")
        // and its window ids ("reset-<epoch>") carry no duration; the card
        // sits inside the "Gemini" section already, so the prefix goes.
        let json = """
        { "reports": [ {
            "provider": "google-gemini-cli",
            "limits": [ {
              "label": "Gemini gemini-2.5-pro",
              "scope": { "provider": "google-gemini-cli", "windowId": "reset-1784310000000" },
              "window": { "id": "reset-1784310000000", "label": "Quota window", "resetsAt": 1784310000000 },
              "amount": { "usedFraction": 0.3, "remainingFraction": 0.7 }
            } ]
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Gemini reset-1784310000000")))

        #expect(quota.compactTitle == "gemini-2.5-pro")
    }

    @Test
    func `keeps meter words off self-describing card titles`() throws {
        // Copilot meters three request pools over one "monthly" window;
        // each label already names its resource, so the shared-window meter
        // prefix must not double it ("Requests Premium Requests").
        let json = """
        { "reports": [ {
            "provider": "github-copilot",
            "limits": [
              {
                "label": "Premium Requests",
                "scope": { "windowId": "monthly" },
                "window": { "id": "monthly", "label": "Monthly" },
                "amount": { "usedFraction": 0.1, "remainingFraction": 0.9, "unit": "requests" }
              },
              {
                "label": "Chat Requests",
                "scope": { "windowId": "monthly" },
                "window": { "id": "monthly", "label": "Monthly" },
                "amount": { "usedFraction": 0.2, "remainingFraction": 0.8, "unit": "requests" }
              }
            ]
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let titles = snapshot.quotas.compactMap(\.compactTitle)

        #expect(titles == ["Premium Requests", "Chat Requests"])
    }

    @Test
    func `degrades oversized window durations to the label instead of trapping`() throws {
        // durationMs is attacker-adjacent external JSON; a finite value past
        // Int.max must fall through to the label fallback, not crash the
        // Int conversion.
        let json = """
        { "reports": [ {
            "provider": "kimi-code",
            "limits": [ {
              "label": "Broken window",
              "scope": { "windowId": "broken_machine_id" },
              "window": { "id": "broken_machine_id", "durationMs": 1.0e308 },
              "amount": { "usedFraction": 0.5, "remainingFraction": 0.5 }
            } ]
        } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Kimi broken_machine_id")))

        #expect(quota.compactTitle == "Broken window")
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

    @Test
    func `suppresses unreported account with matching account id`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "accountId": "account-123" }
        } ],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "accountId": "account-123" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `suppresses unreported account matching scoped account id`() throws {
        let json = """
        { "reports": [ {
            "provider": "google-gemini-cli",
            "limits": [ {
              "scope": {
                "windowId": "1d",
                "accountId": "scoped-account-123"
              },
              "window": { "id": "1d" },
              "amount": { "remainingFraction": 0.9 }
            } ]
        } ],
          "accountsWithoutUsage": [
            {
              "provider": "google-gemini-cli",
              "type": "oauth",
              "accountId": "scoped-account-123"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `matching account id on different provider does not suppress unreported account`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "accountId": "shared-account-id" }
        } ],
          "accountsWithoutUsage": [
            {
              "provider": "github-copilot",
              "type": "oauth",
              "accountId": "shared-account-id"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Copilot · shared-account-id"])
    }

    @Test
    func `suppresses unreported account with normalized matching email`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "email": " Alice@Example.COM " }
        } ],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "alice@example.com" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `matching email overrides different credential account ids`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": {
              "email": "alice@example.com",
              "accountId": "report-credential-id"
            }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "anthropic",
            "type": "oauth",
            "email": "alice@example.com",
            "accountId": "stale-credential-id"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `same email with differing organization keeps unreported account visible`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": {
              "email": "alice@example.com",
              "orgId": "reported-org"
            }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "anthropic",
            "type": "oauth",
            "email": "alice@example.com",
            "orgId": "unreported-org"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · alice@example.com"])
    }

    @Test
    func `same email and organization keeps upstream unreported account visible`() throws {
        // omp's org gate normally absorbs this identity into the same-org
        // report. If it still reaches ClaudeBar, preserve omp's decision to
        // surface the failed fetch instead of second-guessing it by email.
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": {
              "email": "alice@example.com",
              "orgId": "same-org"
            }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "anthropic",
            "type": "oauth",
            "email": "alice@example.com",
            "orgId": "same-org"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · alice@example.com"])
    }

    @Test
    func `organization-scoped account id match keeps unreported account visible`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "accountId": "shared-account-id" }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "anthropic",
            "type": "oauth",
            "accountId": "shared-account-id",
            "orgId": "unreported-org"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · shared-account-id"])
    }

    @Test
    func `same email on different provider does not suppress unreported account`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "email": "shared@example.com" }
        } ],
          "accountsWithoutUsage": [
            { "provider": "github-copilot", "type": "oauth", "email": "shared@example.com" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Copilot · shared@example.com"])
    }

    @Test
    func `different identities on one provider both render`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": {
              "email": "alice@example.com",
              "accountId": "alice-credential"
            }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "anthropic",
            "type": "oauth",
            "email": "bob@example.com",
            "accountId": "bob-credential"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · bob@example.com"])
        #expect(snapshot.quotaGroups.map(\.title) == ["Claude", "Claude · bob"])
    }

    @Test
    func `different emails do not fall back to matching account id`() throws {
        let json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": {
              "email": "alice@example.com",
              "accountId": "shared-credential-id"
            }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "anthropic",
            "type": "oauth",
            "email": "bob@example.com",
            "accountId": "shared-credential-id"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · bob@example.com"])
    }

    @Test
    func `shared project id does not suppress unreported account`() throws {
        let json = """
        { "reports": [ {
            "provider": "google-gemini-cli",
            "limits": [ {
              "scope": { "windowId": "1d" },
              "window": { "id": "1d" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": { "projectId": "shared-project" }
        } ],
          "accountsWithoutUsage": [ {
            "provider": "google-gemini-cli",
            "type": "oauth",
            "projectId": "shared-project"
          } ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Gemini · shared-project"])
    }

    @Test
    func `identical whitespace emails with different account ids stay distinct`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": " ",
              "accountId": "first-credential"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": " ",
              "accountId": "second-credential"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.count == 2)
    }

    @Test
    func `identical whitespace emails fall back to identical account ids`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": " ",
              "accountId": "same-credential"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": " ",
              "accountId": "same-credential"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.count == 1)
    }

    @Test
    func `duplicate identified unreported accounts collapse to one row`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "first-credential"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": " ALICE@example.com ",
              "accountId": "second-credential"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let metrics = try #require(snapshot.extensionMetrics)

        #expect(metrics.count == 1)
        #expect(metrics[0].label == "Claude · alice@example.com")
    }

    @Test
    func `organization-scoped unreported accounts with same email both render`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "first-credential",
              "orgId": "first-org"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "second-credential",
              "orgId": "second-org"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.count == 2)
    }

    @Test
    func `mixed organization and legacy unreported accounts stay distinct regardless of order`() throws {
        let organizationFirst = """
        { "reports": [],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "organization-credential",
              "orgId": "organization"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "legacy-credential"
            }
          ] }
        """
        let legacyFirst = """
        { "reports": [],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "legacy-credential"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "organization-credential",
              "orgId": "organization"
            }
          ] }
        """

        let organizationFirstSnapshot = try OmpUsageProbe.parse(organizationFirst)
        let legacyFirstSnapshot = try OmpUsageProbe.parse(legacyFirst)

        #expect(organizationFirstSnapshot.extensionMetrics?.count == 2)
        #expect(legacyFirstSnapshot.extensionMetrics?.count == 2)
    }

    @Test
    func `zero-limit report identity suppresses matching unreported account`() throws {
        let json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": [],
            "metadata": { "email": "local@ollama.dev" }
        } ],
          "accountsWithoutUsage": [
            { "provider": "ollama", "type": "oauth", "email": "LOCAL@OLLAMA.DEV" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Ollama · local@ollama.dev"])
        #expect(snapshot.quotaGroups.map(\.title) == ["Ollama · local"])
    }

    @Test
    func `anonymous unreported account never matches anonymous report`() throws {
        let json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": []
        } ],
          "accountsWithoutUsage": [
            { "provider": "ollama", "type": "oauth" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == [
            "Ollama · account 1",
            "Ollama · OAuth account",
        ])
    }

    @Test
    func `live duplicate shape keeps two quota groups and drops stale rows`() throws {
        let json = """
        { "reports": [
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.9 }
            } ],
            "metadata": {
              "email": "alice@example.com",
              "accountId": "alice-report-credential"
            }
          },
          {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "5h" },
              "window": { "id": "5h" },
              "amount": { "remainingFraction": 0.4 }
            } ],
            "metadata": {
              "email": "bob@example.com",
              "accountId": "bob-report-credential"
            }
          }
        ],
          "accountsWithoutUsage": [
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "alice@example.com",
              "accountId": "alice-stale-credential"
            },
            {
              "provider": "anthropic",
              "type": "oauth",
              "email": "bob@example.com",
              "accountId": "bob-stale-credential"
            }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotaGroups.map(\.title) == ["Claude · alice", "Claude · bob"])
        #expect(snapshot.extensionMetrics == nil)
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
        // Section titles stay clean per account — no bogus "(2)" suffixes
        // from quota-group reservations that never emitted quotas.
        let snapshot2 = try OmpUsageProbe.parse(json)
        #expect(snapshot2.extensionMetrics?.map(\.group) == ["Ollama · #1", "Ollama · #2"])
        #expect(snapshot2.hasQuotaGroups == true)
        #expect(snapshot2.quotaGroups.map(\.title) == ["Ollama · #1", "Ollama · #2"])
    }

    // MARK: - Grouping Metadata

    @Test
    func `quotas carry group and compact title for sectioned rendering`() throws {
        let snapshot = try OmpUsageProbe.parse(Self.sampleResponse)

        let claude5h = try #require(snapshot.quota(for: .timeLimit("Claude 5h")))
        #expect(claude5h.group == "Claude")
        #expect(claude5h.compactTitle == "5h")

        let spark = try #require(snapshot.quota(for: .timeLimit("Codex Spark 5h")))
        #expect(spark.group == "Codex")
        #expect(spark.compactTitle == "Spark 5h")

        let fable = try #require(snapshot.quota(for: .timeLimit("Claude Fable 7d")))
        #expect(fable.compactTitle == "Fable 7d")

        // Three upstream providers → three sections, in payload order.
        #expect(snapshot.quotaGroups.map(\.title) == ["Codex", "Claude", "Z.ai"])
    }

    @Test
    func `duplicate accounts get per-account groups`() throws {
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

        #expect(snapshot.quotaGroups.map(\.title) == ["Claude · work", "Claude · home"])
        // Card titles inside a section drop the account context entirely.
        #expect(snapshot.quotas.allSatisfy { $0.compactTitle == "5h" })
    }

    @Test
    func `account rows join grouped sections with short identities`() throws {
        let json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": [],
            "metadata": { "email": "local@ollama.dev" }
        } ],
          "accountsWithoutUsage": [
            { "provider": "github-copilot", "type": "oauth", "email": "work@example.com" }
          ] }
        """
        let snapshot = try OmpUsageProbe.parse(json)
        let metrics = try #require(snapshot.extensionMetrics)

        #expect(metrics.map(\.group) == ["Ollama · local", "Copilot · work"])
        // Sections carry the note inline; no quota cards exist.
        let groups = snapshot.quotaGroups
        #expect(groups.map(\.title) == ["Ollama · local", "Copilot · work"])
        #expect(groups.allSatisfy { $0.quotas.isEmpty && $0.note == "No usage reported" })
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
    func `throws parseFailed on malformed output`() throws {
        // Pin the exact error so a regression to `noData` (or any other
        // case) fails instead of passing as "some ProbeError".
        #expect(throws: ProbeError.parseFailed("No JSON object in omp usage output")) {
            try OmpUsageProbe.parse("not json at all")
        }

        // A JSON object whose reports can't decode (missing `provider`)
        // is a decode failure - parseFailed, never an empty-pool noData.
        do {
            _ = try OmpUsageProbe.parse("{ \"reports\": [ { } ] }")
            Issue.record("Expected parse to throw on an undecodable report")
        } catch let error as ProbeError {
            guard case .parseFailed(let message) = error else {
                Issue.record("Expected parseFailed, got \(error)")
                return
            }
            #expect(message.hasPrefix("Malformed omp usage JSON"))
        }
    }

    @Test
    func `throws noData when no accounts are authenticated`() {
        #expect(throws: ProbeError.noData) {
            try OmpUsageProbe.parse("{ \"reports\": [] }")
        }
    }
}
