import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// `omp usage --json` read by `omp-usage.js`, through Oh My Pi's definition.
enum OmpFixtures {
    static func parse(_ text: String) throws -> UsageSnapshot {
        let definition = try ProviderFactory.builtIn("omp")
        let source = DataSources.make(definition.dataSources[0], providerId: "omp", scripts: ProviderFactory.builtInScripts,
                                      environment: { _ in nil })
        do { return try source.read(Response(text: text)) }
        catch let error as DataSourceError { throw error.reason }
    }

    /// The name a provider id is shown with, read through a one-limit report.
    static func displayName(_ id: String) throws -> String? {
        let snapshot = try parse(#"{"reports":[{"provider":"\#(id)","limits":[{"scope":{"windowId":"5h"},"amount":{"remainingFraction":0.5}}]}]}"#)
        return snapshot.quotas.first?.group
    }
}

/// The old probe's fixtures, quota for quota. Card and menu-bar titles are the
/// page's, not the usage's, so they are no longer checked here.
@Suite("Oh My Pi usage")
struct OmpDefinitionTests {

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
    func `should show a quota for every limit omp reports, all as Oh My Pi's`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)

        #expect(snapshot.providerId == "omp")
        #expect(snapshot.quotas.count == 7)
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "omp" })
    }

    @Test
    func `should show the percent left that omp reports as a fraction`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)

        #expect(snapshot.quota(for: .timeLimit("Claude 5h"))?.percentRemaining == 92.0)
        #expect(snapshot.quota(for: .timeLimit("Codex 7d"))?.percentRemaining == 42.0)
        // Fraction-only amounts (no used/limit pair) still map
        #expect(snapshot.quota(for: .timeLimit("Z.ai 5h"))?.percentRemaining == 75.0)
    }

    @Test
    func `should name each quota by its provider, tier and window`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.contains("Claude 5h"))
        #expect(labels.contains("Claude Fable 7d"))
        #expect(labels.contains("Codex Spark 5h"))
        #expect(labels.contains("Z.ai 1mo"))
    }

    @Test
    func `should show the reset time omp gives in epoch milliseconds`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)
        let claude = try #require(snapshot.quota(for: .timeLimit("Claude 5h")))

        #expect(claude.resetsAt == Date(timeIntervalSince1970: 1_783_885_200))
    }

    @Test
    func `should keep each limit's window length so pace can be shown`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)

        #expect(snapshot.quota(for: .timeLimit("Claude 5h"))?.windowDuration == 18_000)
        #expect(snapshot.quota(for: .timeLimit("Codex 7d"))?.windowDuration == 604_800)
    }

    @Test
    func `should show no reset when a limit has no reset time`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)
        let zai = try #require(snapshot.quota(for: .timeLimit("Z.ai 5h")))

        #expect(zai.resetsAt == nil)
    }

    // MARK: - Monetary Limits

    @Test
    func `should show a capped spend limit with nothing spent as a full dollar quota in its provider's group`() throws {
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

        let snapshot = try OmpFixtures.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Claude Extra")))

        #expect(quota.percentRemaining == 100)
        #expect(quota.dollarUsed == 0)
        #expect(quota.dollarCap == 500)
        #expect(quota.group == "Claude")
    }

    @Test
    func `should show a capped spend limit as dollars left of its cap, in rounded dollars`() throws {
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

        let snapshot = try OmpFixtures.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Claude Extra")))

        // Money left of its cap is the measure (the Left law): $376.55 of $500,
        // whatever fraction omp reports beside it.
        #expect(quota.left == .money(Money(Decimal(string: "376.55")!, currency: "USD"), of: Money(500, currency: "USD")))
        #expect(quota.dollarUsed == Decimal(string: "123.45"))
        #expect(quota.dollarCap == 500)
    }

    @Test
    func `should round spend to the cent exactly when it sits on a cent boundary`() throws {
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

        let snapshot = try OmpFixtures.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("Claude Extra")))

        #expect(quota.dollarUsed == Decimal(string: "1.01"))
        #expect(quota.dollarCap == Decimal(string: "12.5"))
        // The share follows the cents shown: (12.50 - 1.01) / 12.50.
        let percent = try #require(quota.percentRemaining)
        #expect(abs(percent - 91.92) < 0.0001)
    }

    @Test
    func `should name a spend limit after its window when omp gives it no label`() throws {
        let json = """
        { "reports": [ {
            "provider": "opencode-go",
            "limits": [ {
              "window": { "id": "monthly" },
              "amount": { "used": 50, "limit": 500, "unit": "usd" }
            } ]
        } ] }
        """

        let snapshot = try OmpFixtures.parse(json)
        let quota = try #require(snapshot.quota(for: .timeLimit("OpenCode Go Monthly")))
        #expect(quota.dollarUsed == 50)
        #expect(quota.dollarCap == 500)
    }

    @Test
    func `should show uncapped spend as a note in its provider's group, not a quota`() throws {
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

        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.isEmpty)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.count == 1)
        #expect(metrics[0].label == "Claude Extra Usage")
        #expect(metrics[0].value == "Extra usage $1,234.56 spent · no cap")
        #expect(metrics[0].group == "Claude")
        #expect(snapshot.quotaGroups.first?.note == "Extra usage $1,234.56 spent · no cap")
    }

    @Test
    func `should name Cursor's windowless spend limits Spend, never USD`() throws {
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

        let snapshot = try OmpFixtures.parse(json)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels == ["Cursor Spend", "Cursor Spend (2)"])
        #expect(labels.allSatisfy { !$0.localizedCaseInsensitiveContains("usd") })
        #expect(snapshot.quotas.first?.dollarUsed == Decimal(string: "1234.56"))
        #expect(snapshot.quotas.first?.dollarCap == 5000)
    }

    @Test
    func `should show a spend limit and a window limit of one account in one group`() throws {
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

        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.quotaType.displayName) == ["Claude 5h", "Claude Extra"])
        #expect(snapshot.quotas.allSatisfy { $0.group == "Claude" })
        #expect(snapshot.quotaGroups.count == 1)
        #expect(snapshot.quotaGroups[0].quotas.count == 2)
    }

    @Test
    func `should tell apart the uncapped spend notes of two accounts on one provider`() throws {
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

        let snapshot = try OmpFixtures.parse(json)
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
    func `should show no email when the accounts have different emails`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)

        #expect(snapshot.accountEmail == nil)
    }

    @Test
    func `should show the email when there is a single account`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.accountEmail == "solo@example.com")
    }

    // MARK: - Multiple Accounts on One Provider

    @Test
    func `should tell apart two accounts on the same provider, each quota unique`() throws {
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
        let snapshot = try OmpFixtures.parse(json)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.contains("Claude 5h · work"))
        #expect(labels.contains("Claude 5h · home"))
        // Quota keys are persisted and used as stable UI identifiers —
        // they must never collide across accounts.
        let keys = Set(snapshot.quotas.map(\.quotaType.quotaKey))
        #expect(keys.count == snapshot.quotas.count)
    }

    @Test
    func `should tell apart two meters sharing one window by what they meter`() throws {
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
        let snapshot = try OmpFixtures.parse(json)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.contains("Z.ai Tokens 5h"))
        #expect(labels.contains("Z.ai Requests 5h"))
        #expect(!labels.contains { $0.hasSuffix("(2)") })
    }

    /// Modeled on live `omp usage --json` output for `google-antigravity`
    /// (omp v18.11.0): Gemini has its own 5-hour and weekly limits, and
    /// Claude and GPT draw on one pool, reported once per model family and
    /// marked `shared` with the same `sharedGroup`. All values are synthetic.
    static let antigravityResponse = """
    { "reports": [ {
        "provider": "google-antigravity",
        "limits": [
          {
            "id": "google-antigravity:google:default:gemini-weekly",
            "label": "Gemini",
            "scope": { "provider": "google-antigravity", "projectId": "test-project", "windowId": "weekly" },
            "window": { "id": "weekly", "label": "Weekly", "durationMs": 604800000, "resetsAt": 1792640089000 },
            "amount": { "unit": "percent", "remainingFraction": 0.9, "usedFraction": 0.1, "remaining": 90, "used": 10, "limit": 100 }
          },
          {
            "id": "google-antigravity:google:default:gemini-5h",
            "label": "Gemini",
            "scope": { "provider": "google-antigravity", "projectId": "test-project", "windowId": "5h" },
            "window": { "id": "5h", "label": "5 Hour", "durationMs": 18000000, "resetsAt": 1792053289000 },
            "amount": { "unit": "percent", "remainingFraction": 0.8, "usedFraction": 0.2, "remaining": 80, "used": 20, "limit": 100 }
          },
          {
            "id": "google-antigravity:anthropic:default:3p-weekly",
            "label": "Claude & GPT (shared)",
            "scope": { "provider": "google-antigravity", "projectId": "test-project", "windowId": "weekly", "shared": true, "sharedGroup": "3p-weekly:weekly" },
            "window": { "id": "weekly", "label": "Weekly", "durationMs": 604800000, "resetsAt": 1792640089000 },
            "amount": { "unit": "percent", "remainingFraction": 0.7, "usedFraction": 0.3, "remaining": 70, "used": 30, "limit": 100 }
          },
          {
            "id": "google-antigravity:openai:default:3p-weekly",
            "label": "Claude & GPT (shared)",
            "scope": { "provider": "google-antigravity", "projectId": "test-project", "windowId": "weekly", "shared": true, "sharedGroup": "3p-weekly:weekly" },
            "window": { "id": "weekly", "label": "Weekly", "durationMs": 604800000, "resetsAt": 1792640089000 },
            "amount": { "unit": "percent", "remainingFraction": 0.7, "usedFraction": 0.3, "remaining": 70, "used": 30, "limit": 100 }
          },
          {
            "id": "google-antigravity:anthropic:default:3p-5h",
            "label": "Claude & GPT (shared)",
            "scope": { "provider": "google-antigravity", "projectId": "test-project", "windowId": "5h", "shared": true, "sharedGroup": "3p-5h:5h" },
            "window": { "id": "5h", "label": "5 Hour", "durationMs": 18000000, "resetsAt": 1792053289000 },
            "amount": { "unit": "percent", "remainingFraction": 0.6, "usedFraction": 0.4, "remaining": 60, "used": 40, "limit": 100 }
          },
          {
            "id": "google-antigravity:openai:default:3p-5h",
            "label": "Claude & GPT (shared)",
            "scope": { "provider": "google-antigravity", "projectId": "test-project", "windowId": "5h", "shared": true, "sharedGroup": "3p-5h:5h" },
            "window": { "id": "5h", "label": "5 Hour", "durationMs": 18000000, "resetsAt": 1792053289000 },
            "amount": { "unit": "percent", "remainingFraction": 0.6, "usedFraction": 0.4, "remaining": 60, "used": 40, "limit": 100 }
          }
        ],
        "metadata": { "projectId": "test-project", "email": "agy@example.com" }
    } ] }
    """

    @Test
    func `should tell apart limits sharing one window by what omp calls each`() throws {
        let snapshot = try OmpFixtures.parse(Self.antigravityResponse)

        #expect(snapshot.quota(for: .timeLimit("Antigravity Gemini weekly"))?.percentRemaining == 90)
        #expect(snapshot.quota(for: .timeLimit("Antigravity Gemini 5h"))?.percentRemaining == 80)
        #expect(snapshot.quota(for: .timeLimit("Antigravity Claude & GPT (shared) weekly"))?.percentRemaining == 70)
        #expect(snapshot.quota(for: .timeLimit("Antigravity Claude & GPT (shared) 5h"))?.percentRemaining == 60)
    }

    @Test
    func `should show a pool omp reports once per model family as one quota`() throws {
        let snapshot = try OmpFixtures.parse(Self.antigravityResponse)
        let labels = snapshot.quotas.map(\.quotaType.displayName)

        #expect(labels.count == 4)
        #expect(!labels.contains { $0.hasSuffix("(2)") })
    }

    @Test
    func `should show a pool from the member that has an amount when the first reports none`() throws {
        let json = """
        { "reports": [ {
            "provider": "google-antigravity",
            "limits": [
              { "label": "Claude & GPT (shared)", "scope": { "windowId": "5h", "sharedGroup": "3p-5h:5h" }, "amount": { "unit": "percent" } },
              { "label": "Claude & GPT (shared)", "scope": { "windowId": "5h", "sharedGroup": "3p-5h:5h" }, "amount": { "remainingFraction": 0.35 } }
            ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.percentRemaining) == [35])
    }

    @Test
    func `should keep limits that share a window but no pool apart`() throws {
        // Same window and label, no sharedGroup: two pools omp names alike.
        let json = """
        { "reports": [ {
            "provider": "google-antigravity",
            "limits": [
              { "label": "Claude", "scope": { "windowId": "5h", "shared": true }, "amount": { "remainingFraction": 0.5 } },
              { "label": "Claude", "scope": { "windowId": "5h", "shared": true }, "amount": { "remainingFraction": 0.4 } }
            ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.percentRemaining) == [50, 40])
    }

    // MARK: - One Quota Reported Twice

    /// Modeled on live `omp usage --json` output for `kimi-code` (omp
    /// v18.14.0). omp builds the weekly row `7d` from Kimi's `usage` summary
    /// and the 5-hour row from its `limits`, then adds each `usages`
    /// aggregate but `limit_5h`, which repeats the 5-hour row; so `limit_7d`,
    /// the same weekly quota with the same reset, arrives a second time.
    /// All values are synthetic.
    static let kimiResponse = """
    { "reports": [ {
        "provider": "kimi-code",
        "limits": [
          {
            "id": "kimi-code:0",
            "label": "Weekly limit",
            "scope": { "provider": "kimi-code", "windowId": "7d", "shared": true },
            "window": { "id": "7d", "label": "7 Day", "resetsAt": 1793781471222 },
            "amount": { "unit": "unknown", "limit": 100, "used": 12, "remaining": 88, "usedFraction": 0.12, "remainingFraction": 0.88 }
          },
          {
            "id": "kimi-code:1",
            "label": "5h limit",
            "scope": { "provider": "kimi-code", "windowId": "5h", "shared": true },
            "window": { "id": "5h", "label": "5h limit", "durationMs": 18000000, "resetsAt": 1793403471222 },
            "amount": { "unit": "unknown", "limit": 100, "used": 3, "remaining": 97, "usedFraction": 0.03, "remainingFraction": 0.97 }
          },
          {
            "id": "kimi-code:2",
            "label": "limit_7d",
            "scope": { "provider": "kimi-code", "windowId": "limit_7d", "shared": true },
            "window": { "id": "limit_7d", "label": "limit_7d", "resetsAt": 1793781470000 },
            "amount": { "unit": "percent", "limit": 100, "used": 12.39, "remaining": 87.61, "usedFraction": 0.1239, "remainingFraction": 0.8761 }
          }
        ],
        "metadata": { "endpoint": "https://api.kimi.com/coding/v1/usages" }
    } ] }
    """

    @Test
    func `should show Kimi's weekly quota once, from its 7d row, when Kimi repeats it as limit_7d`() throws {
        let snapshot = try OmpFixtures.parse(Self.kimiResponse)

        #expect(snapshot.quotas.map(\.quotaType.displayName) == ["Kimi 7d", "Kimi 5h"])
        #expect(snapshot.quota(for: .timeLimit("Kimi 7d"))?.percentRemaining == 88)
    }

    @Test
    func `should keep an aggregate quota when no other row reports its window`() throws {
        let json = """
        { "reports": [ {
            "provider": "kimi-code",
            "limits": [
              { "label": "5h limit", "scope": { "windowId": "5h" }, "amount": { "remainingFraction": 0.97 } },
              { "label": "limit_7d", "scope": { "windowId": "limit_7d" }, "amount": { "unit": "percent", "remainingFraction": 0.8761 } }
            ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.quotaType.displayName) == ["Kimi 5h", "Kimi limit_7d"])
    }

    @Test
    func `should keep an aggregate quota when the row for its window has no amount to show`() throws {
        let json = """
        { "reports": [ {
            "provider": "kimi-code",
            "limits": [
              { "label": "Weekly limit", "scope": { "windowId": "7d" }, "amount": { "unit": "unknown" } },
              { "label": "limit_7d", "scope": { "windowId": "limit_7d" }, "amount": { "unit": "percent", "remainingFraction": 0.8761 } }
            ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.quotaType.displayName) == ["Kimi limit_7d"])
    }

    /// Devin's three credit buckets as omp v18.14.0's `devin.ts` builds
    /// them: one plan tier, one monthly window, `unit: "unknown"`.
    @Test
    func `should never name a quota after an unknown unit`() throws {
        let json = """
        { "reports": [ {
            "provider": "devin",
            "limits": [
              { "label": "Prompt Credits", "scope": { "tier": "Pro", "windowId": "monthly" },
                "amount": { "used": 100, "remaining": 400, "limit": 500, "usedFraction": 0.2, "remainingFraction": 0.8, "unit": "unknown" } },
              { "label": "Flow Credits", "scope": { "tier": "Pro", "windowId": "monthly" },
                "amount": { "used": 300, "remaining": 700, "limit": 1000, "usedFraction": 0.3, "remainingFraction": 0.7, "unit": "unknown" } },
              { "label": "Flex Credits", "scope": { "tier": "Pro", "windowId": "monthly" },
                "amount": { "used": 0, "remaining": 50, "limit": 50, "usedFraction": 0, "remainingFraction": 1, "unit": "unknown" } }
            ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.quotaType.displayName)
            == ["Devin Pro Prompt Credits monthly", "Devin Pro Flow Credits monthly", "Devin Pro Flex Credits monthly"])
    }

    // MARK: - Balances

    /// Command Code's pay-as-you-go account as omp v18.14.0's
    /// `commandcode.ts` reports it: a credit balance and no limit.
    @Test
    func `should show a credit balance with no limit as the credits left`() throws {
        let json = """
        { "reports": [ {
            "provider": "commandcode",
            "limits": [ {
              "id": "commandcode:balance", "label": "Credit balance",
              "scope": { "provider": "commandcode", "windowId": "balance", "shared": true },
              "amount": { "remaining": 1234.5, "unit": "credits" }
            } ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.isEmpty)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Command Code Credit balance"])
        #expect(metrics.map(\.value) == ["1,234.5 credits left"])
        #expect(metrics.map(\.group) == ["Command Code"])
    }

    @Test
    func `should show a balance in an unknown unit as a bare number left`() throws {
        let json = """
        { "reports": [ {
            "provider": "devin",
            "limits": [ { "label": "Flex Credits", "scope": { "windowId": "monthly" }, "amount": { "used": 0, "remaining": 120, "unit": "unknown" } } ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(try #require(snapshot.extensionMetrics).map(\.value) == ["120 left"])
    }

    @Test
    func `should show a dollar balance with no limit as dollars left`() throws {
        let json = """
        { "reports": [ {
            "provider": "cursor",
            "limits": [ { "label": "Prepaid", "scope": { "windowId": "prepaid" }, "amount": { "remaining": 12.5, "unit": "usd" } } ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(try #require(snapshot.extensionMetrics).map(\.value) == ["$12.50 left"])
    }

    @Test
    func `should show what is left of a capped limit as a quota, not a balance`() throws {
        let json = """
        { "reports": [ {
            "provider": "commandcode",
            "limits": [ { "label": "Monthly credits", "scope": { "windowId": "monthly" }, "amount": { "remaining": 80, "limit": 100, "unit": "credits" } } ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics == nil)
        #expect(snapshot.quota(for: .timeLimit("Command Code monthly"))?.percentRemaining == 80)
    }

    @Test
    func `should show dollars left of a cap as dollars left of that cap, not a balance`() throws {
        let json = """
        { "reports": [ {
            "provider": "cursor",
            "limits": [ { "label": "Included", "scope": { "windowId": "monthly" }, "amount": { "remaining": 80.25, "limit": 100, "unit": "usd" } } ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics == nil)
        let quota = try #require(snapshot.quotas.first)
        #expect(quota.left == .money(Money(Decimal(string: "80.25")!, currency: "USD"), of: Money(100, currency: "USD")))
    }

    @Test
    func `should round the dollars left that omp reports, not the spend worked out from them`() throws {
        let json = """
        { "reports": [ {
            "provider": "cursor",
            "limits": [ { "label": "Included", "scope": { "windowId": "monthly" }, "amount": { "remaining": 80.255, "limit": 100, "unit": "usd" } } ]
        } ] }
        """
        let quota = try #require(try OmpFixtures.parse(json).quotas.first)

        #expect(quota.left == .money(Money(Decimal(string: "80.26")!, currency: "USD"), of: Money(100, currency: "USD")))
    }

    @Test
    func `should show a balance beside the windows of the same account`() throws {
        let json = """
        { "reports": [ {
            "provider": "commandcode",
            "limits": [
              { "label": "5-hour limit", "scope": { "windowId": "5h" }, "window": { "id": "5h", "durationMs": 18000000 },
                "amount": { "used": 20, "limit": 100, "usedFraction": 0.2, "unit": "credits" } },
              { "label": "Credit balance", "scope": { "windowId": "balance" }, "amount": { "remaining": 94, "unit": "credits" } }
            ]
        } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.quotaType.displayName) == ["Command Code 5h"])
        #expect(try #require(snapshot.extensionMetrics).map(\.value) == ["94 credits left"])
    }

    // MARK: - Saved Resets

    /// The day a saved reset expires, on the person's clock.
    static func day(_ iso: String) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: try #require(ISO8601DateFormatter().date(from: iso)))
    }

    /// Codex's saved reset as omp v18.14.0 reports it (`resetCredits`, a
    /// report field), beside a Claude account with none.
    @Test
    func `should show an account's saved resets and when the next one expires`() throws {
        let json = """
        { "reports": [
          { "provider": "openai-codex",
            "limits": [ { "scope": { "windowId": "7d" }, "amount": { "remainingFraction": 0.9 } } ],
            "resetCredits": { "availableCount": 1, "credits": [
              { "grantedAt": "2099-10-07T23:37:12.034262Z", "expiresAt": "2099-11-06T12:00:00.000000Z", "status": "available" } ] } },
          { "provider": "anthropic",
            "limits": [ { "scope": { "windowId": "5h" }, "amount": { "remainingFraction": 0.9 } } ],
            "resetCredits": { "availableCount": 0, "redeemableCount": 0, "eligible": false, "reason": "no_grant", "credits": [] } }
        ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Codex Saved resets"])
        #expect(metrics.map(\.value) == ["1 saved reset · next expires \(try Self.day("2099-11-06T12:00:00Z"))"])
        #expect(metrics.map(\.group) == ["Codex"])
    }

    @Test
    func `should say how many saved resets can be used now, and expire next, when some can't be used`() throws {
        let json = """
        { "reports": [ { "provider": "anthropic", "limits": [],
            "resetCredits": { "availableCount": 2, "redeemableCount": 1, "credits": [
              { "expiresAt": "2000-01-01T12:00:00Z" },
              { "expiresAt": "2099-12-24T12:00:00Z" },
              { "expiresAt": "2099-12-03T12:00:00Z" } ] } } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.value) == ["2 saved resets · 1 usable now · next expires \(try Self.day("2099-12-03T12:00:00Z"))"])
    }

    @Test
    func `should show an account's saved resets, not no usage, when it reported nothing else`() throws {
        let json = """
        { "reports": [ { "provider": "anthropic", "limits": [], "resetCredits": { "availableCount": 1 } } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(try #require(snapshot.extensionMetrics).map(\.value) == ["1 saved reset"])
    }

    @Test
    func `should tell apart the saved resets of two accounts on one provider`() throws {
        let json = """
        { "reports": [
          { "provider": "openai-codex", "limits": [], "metadata": { "email": "work@example.com" }, "resetCredits": { "availableCount": 1 } },
          { "provider": "openai-codex", "limits": [], "metadata": { "email": "home@example.com" }, "resetCredits": { "availableCount": 1 } }
        ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Codex Saved resets · work", "Codex Saved resets · home"])
        #expect(metrics.map(\.group) == ["Codex · work", "Codex · home"])
    }

    // MARK: - Signed-Out Accounts

    /// Josh's real cause, a refresh omp's Anthropic sign-in could no longer
    /// make, with its URLs kept and its stack cut.
    static let refreshFailure = #"oauth refresh failed: OAuthError: Anthropic token refresh request failed. url=https://api.anthropic.com/v1/oauth/token; details=ProviderHttpError: HTTP request failed. status=400; url=https://api.anthropic.com/v1/oauth/token; body={\"error\": \"invalid_grant\", \"error_description\": \"Refresh token not found or invalid\"}"#

    @Test
    func `should show an account omp signed out, and why, instead of dropping it`() throws {
        let json = """
        { "reports": [ { "provider": "anthropic", "limits": [ { "scope": { "windowId": "5h" }, "amount": { "remainingFraction": 0.9 } } ],
                         "metadata": { "email": "active@example.com" } } ],
          "accountsWithoutUsage": [],
          "disabledCredentials": [
            { "id": 7, "provider": "anthropic", "type": "oauth", "email": "lapsed@example.com", "cause": "\(Self.refreshFailure)", "disabledAtMs": 1793000000000 }
          ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.group) == ["Claude"])
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Claude · lapsed@example.com"])
        #expect(metrics.map(\.value) == ["Signed out · Refresh token not found or invalid · run omp login"])
        #expect(metrics.map(\.group) == ["Claude · lapsed"])
        #expect(snapshot.accountEmail == "active@example.com")
    }

    @Test(arguments: [
        ("upstream reported invalidated OAuth token", "Signed out · upstream reported invalidated OAuth token · run omp login"),
        ("oauth refresh failed: OAuthError: Anthropic token refresh request failed. url=https://api.anthropic.com/v1/oauth/token; details=timeout",
         "Signed out · Anthropic token refresh request failed · run omp login"),
        ("", "Signed out · run omp login"),
    ])
    func `should say in a few words why omp signed an account out`(cause: String, expected: String) throws {
        let json = """
        { "reports": [], "disabledCredentials": [ { "provider": "openai-codex", "type": "oauth", "accountId": "acct-1", "cause": "\(cause)" } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(try #require(snapshot.extensionMetrics).map(\.value) == [expected])
    }

    @Test
    func `should show one row for an account omp signed out twice`() throws {
        let json = """
        { "reports": [], "disabledCredentials": [
            { "provider": "anthropic", "type": "oauth", "email": "lapsed@example.com", "cause": "upstream reported invalidated OAuth token" },
            { "provider": "anthropic", "type": "oauth", "email": "Lapsed@example.com", "cause": "upstream reported invalidated OAuth token" },
            { "provider": "anthropic", "type": "oauth", "email": "lapsed@example.com", "orgId": "org-team", "orgName": "Team", "cause": "upstream reported invalidated OAuth token" }
        ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Claude · lapsed@example.com", "Claude · lapsed@example.com · Team"])
        #expect(snapshot.accountEmail == nil)
    }

    // MARK: - Accounts Without Usage

    @Test
    func `should show no account rows when every account reported usage`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)

        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `should show the quotas and a no-usage row for an account that reported none`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 1)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.count == 1)
        #expect(metrics[0].label == "Copilot · work@example.com")
        #expect(metrics[0].value == "No usage reported")
    }

    /// Qwen Cloud's Token Plan, signed into omp with its API key alone, as
    /// `omp usage --json` reports it (omp v18.10): omp reads that plan's quota
    /// only through the Qwen Cloud console's cookie, given at `omp login`. An
    /// expired cookie or a failed fetch reads the same, so the row names what
    /// to check, not a certain cause.
    @Test
    func `should name Qwen Cloud's Token Plan and point at omp's console cookie when omp reports no usage`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [ { "provider": "alibaba-token-plan", "type": "api_key" } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Qwen Cloud · API key"])
        #expect(metrics[0].value == "No usage · check omp's console cookie")
    }

    /// The same plan with the console cookie: omp's two windows, as its
    /// `alibaba-token-plan` usage provider builds them.
    @Test
    func `should show Qwen Cloud's Token Plan's 5-hour and weekly credits when omp reports them`() throws {
        let json = """
        { "reports": [ {
            "provider": "alibaba-token-plan",
            "fetchedAt": 1791820000000,
            "limits": [
              { "id": "credits:5h", "label": "5 Hour Credits",
                "scope": { "provider": "alibaba-token-plan", "windowId": "5h" },
                "window": { "id": "5h", "label": "5 Hour Credits", "durationMs": 18000000, "resetsAt": 1791830000000 },
                "amount": { "used": 42, "usedFraction": 0.42, "unit": "percent" }, "status": "ok" },
              { "id": "credits:7d", "label": "7 Day Credits",
                "scope": { "provider": "alibaba-token-plan", "windowId": "7d" },
                "window": { "id": "7d", "label": "7 Day Credits", "durationMs": 604800000, "resetsAt": 1792300000000 },
                "amount": { "used": 81, "usedFraction": 0.81, "unit": "percent" }, "status": "warning" }
            ],
            "metadata": { "source": "qwencloud-console" } } ],
          "accountsWithoutUsage": [] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.map(\.group) == ["Qwen Cloud", "Qwen Cloud"])
        #expect(snapshot.quotas.map { Int($0.percentRemaining.rounded()) } == [58, 19])
        #expect(snapshot.quotas.map(\.resetsAt) == [Date(timeIntervalSince1970: 1_791_830_000), Date(timeIntervalSince1970: 1_792_300_000)])
        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `should still say only that no usage was reported for a key omp has no setup hint for`() throws {
        let json = """
        { "reports": [], "accountsWithoutUsage": [ { "provider": "zai", "type": "api_key" } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(try #require(snapshot.extensionMetrics).map(\.value) == ["No usage reported"])
    }

    @Test
    func `should show a no-usage row for each account, not no data, when none reported usage`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "solo@example.com" },
            { "provider": "openai-codex", "type": "api_key" }
          ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.isEmpty)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Claude · solo@example.com", "Codex · API key"])
        #expect(metrics.allSatisfy { $0.value == "No usage reported" })
    }

    @Test
    func `should give each anonymous account on one provider its own row name`() throws {
        // MenuContentView keys these cards by label — collisions would
        // hide or reuse rows.
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "openai-codex", "type": "api_key" },
            { "provider": "openai-codex", "type": "api_key" }
          ] }
        """
        let snapshot = try OmpFixtures.parse(json)
        let labels = try #require(snapshot.extensionMetrics).map(\.label)

        #expect(labels == ["Codex · API key", "Codex · API key (2)"])
        #expect(Set(labels).count == labels.count)
    }

    @Test
    func `should show the email of the single account even when it reported no usage`() throws {
        let json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "solo@example.com" }
          ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.accountEmail == "solo@example.com")
    }

    @Test
    func `should show no no-usage row for an account that also reported usage under the same account id`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `should show no no-usage row for an account whose id a limit already reported`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `should show the no-usage row when the same account id reported usage on another provider`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Copilot · shared-account-id"])
    }

    @Test
    func `should show no no-usage row when the same email, in any case or spacing, reported usage`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `should show no no-usage row when the same email reported usage under another credential`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics == nil)
    }

    @Test
    func `should show the no-usage row when the same email reported usage for another organization`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · alice@example.com"])
    }

    @Test
    func `should show the no-usage row when omp reports it even for the same email and organization`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · alice@example.com"])
    }

    @Test
    func `should show the no-usage row when the matching account id belongs to an organization`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · shared-account-id"])
    }

    @Test
    func `should show the no-usage row when the same email reported usage on another provider`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Copilot · shared@example.com"])
    }

    @Test
    func `should show both a reported account and an unreported one on the same provider`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · bob@example.com"])
        #expect(snapshot.quotaGroups.map(\.title) == ["Claude", "Claude · bob"])
    }

    @Test
    func `should show the no-usage row when the emails differ even though the account id matches`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Claude · bob@example.com"])
    }

    @Test
    func `should show the no-usage row when only a project id is shared`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Gemini · shared-project"])
    }

    @Test
    func `should show two rows for blank-email accounts with different account ids`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.count == 2)
    }

    @Test
    func `should show one row for blank-email accounts with the same account id`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.count == 1)
    }

    @Test
    func `should show one row for unreported accounts with the same email`() throws {
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
        let snapshot = try OmpFixtures.parse(json)
        let metrics = try #require(snapshot.extensionMetrics)

        #expect(metrics.count == 1)
        #expect(metrics[0].label == "Claude · alice@example.com")
    }

    @Test
    func `should show a row for each organization when one email has two`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.count == 2)
    }

    @Test
    func `should show an organization account and a legacy one with the same email as two rows, in either order`() throws {
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

        let organizationFirstSnapshot = try OmpFixtures.parse(organizationFirst)
        let legacyFirstSnapshot = try OmpFixtures.parse(legacyFirst)

        #expect(organizationFirstSnapshot.extensionMetrics?.count == 2)
        #expect(legacyFirstSnapshot.extensionMetrics?.count == 2)
    }

    @Test
    func `should show one row when an account with no limits is also listed as unreported`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Ollama · local@ollama.dev"])
        #expect(snapshot.quotaGroups.map(\.title) == ["Ollama · local"])
    }

    @Test
    func `should show an anonymous unreported account apart from an anonymous report`() throws {
        let json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": []
        } ],
          "accountsWithoutUsage": [
            { "provider": "ollama", "type": "oauth" }
          ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == [
            "Ollama · account 1",
            "Ollama · OAuth account",
        ])
    }

    @Test
    func `should show one group per account and no stale rows when each account reported under a new credential`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotaGroups.map(\.title) == ["Claude · alice", "Claude · bob"])
        #expect(snapshot.extensionMetrics == nil)
    }

    // MARK: - Reports Without Usable Limits

    @Test
    func `should still list an account whose report has no limits`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 1)
        let metrics = try #require(snapshot.extensionMetrics)
        #expect(metrics.map(\.label) == ["Ollama · local@ollama.dev"])
        #expect(metrics[0].value == "No usage reported")
    }

    @Test
    func `should show account rows, not no data, when every report has no limits`() throws {
        let json = """
        { "reports": [ { "provider": "ollama", "limits": [] } ] }
        """
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.extensionMetrics?.map(\.label) == ["Ollama · account 1"])
    }

    @Test
    func `should name an account after its limits when its report carries no identity`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.extensionMetrics?.map(\.label) == ["Gemini · my-gcp-project"])
    }

    @Test
    func `should show anonymous accounts with no limits on one provider as numbered sections`() throws {
        let json = """
        { "reports": [
            { "provider": "ollama", "limits": [] },
            { "provider": "ollama", "limits": [] }
        ] }
        """
        let snapshot = try OmpFixtures.parse(json)
        let labels = try #require(snapshot.extensionMetrics).map(\.label)

        #expect(labels == ["Ollama · #1", "Ollama · #2"])
        #expect(Set(labels).count == labels.count)
        // Section titles stay clean per account — no bogus "(2)" suffixes
        // from quota-group reservations that never emitted quotas.
        let snapshot2 = try OmpFixtures.parse(json)
        #expect(snapshot2.extensionMetrics?.map(\.group) == ["Ollama · #1", "Ollama · #2"])
        #expect(snapshot2.hasQuotaGroups == true)
        #expect(snapshot2.quotaGroups.map(\.title) == ["Ollama · #1", "Ollama · #2"])
    }

    // MARK: - Grouping Metadata

    @Test
    func `should group quotas into one section per provider, in the order omp reports them`() throws {
        let snapshot = try OmpFixtures.parse(Self.sampleResponse)

        let claude5h = try #require(snapshot.quota(for: .timeLimit("Claude 5h")))
        #expect(claude5h.group == "Claude")

        let spark = try #require(snapshot.quota(for: .timeLimit("Codex Spark 5h")))
        #expect(spark.group == "Codex")

        let fable = try #require(snapshot.quota(for: .timeLimit("Claude Fable 7d")))

        // Three upstream providers → three sections, in payload order.
        #expect(snapshot.quotaGroups.map(\.title) == ["Codex", "Claude", "Z.ai"])
    }

    @Test
    func `should show a section per account when one provider has two`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotaGroups.map(\.title) == ["Claude · work", "Claude · home"])
        // Card titles inside a section drop the account context entirely.
    }

    @Test
    func `should show no-usage accounts as their own sections, named by short identities`() throws {
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
        let snapshot = try OmpFixtures.parse(json)
        let metrics = try #require(snapshot.extensionMetrics)

        #expect(metrics.map(\.group) == ["Ollama · local", "Copilot · work"])
        // Sections carry the note inline; no quota cards exist.
        let groups = snapshot.quotaGroups
        #expect(groups.map(\.title) == ["Ollama · local", "Copilot · work"])
        #expect(groups.allSatisfy { $0.quotas.isEmpty && $0.note == "No usage reported" })
    }

    // MARK: - Upstream Display Names

    @Test(arguments: [
        // Every id omp v18.14's usage registry emits (@oh-my-pi/pi-ai/src/usage/*).
        ("alibaba-token-plan", "Qwen Cloud"),
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
        ("cursor", "Cursor"),
        ("synthetic", "Synthetic"),
        ("umans", "Umans"),
        ("xai-oauth", "Grok"),
        ("commandcode", "Command Code"),
        ("cline-pass", "ClinePass"),
        ("charm-hyper", "Charm Hyper"),
        ("devin", "Devin"),
        ("factory-droid", "Factory Droid"),
        ("muse-code", "Muse Code"),
    ])
    func `should show every provider omp reports by its display name`(id: String, expected: String) throws {
        #expect(try OmpFixtures.displayName(id) == expected)
    }

    // MARK: - Robustness

    @Test
    func `should read the usage when omp prints other lines around it`() throws {
        let noisy = "Synced 3 accounts\n\(Self.sampleResponse)\nDone."
        let snapshot = try OmpFixtures.parse(noisy)

        #expect(snapshot.quotas.count == 7)
    }

    @Test
    func `should skip a limit with no usable amount`() throws {
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
        let snapshot = try OmpFixtures.parse(json)

        #expect(snapshot.quotas.count == 1)
    }

    @Test
    func `should fail to read usage when omp prints something that is not usage`() throws {
        // Pin the exact error so a regression to `noData` (or any other
        // case) fails instead of passing as "some UsageError".
        #expect(throws: UsageError.parseFailed("No JSON object in omp usage output")) {
            try OmpFixtures.parse("not json at all")
        }

        // A JSON object whose reports can't decode (missing `provider`)
        // is a decode failure - parseFailed, never an empty-pool noData.
        do {
            _ = try OmpFixtures.parse("{ \"reports\": [ { } ] }")
            Issue.record("Expected parse to throw on an undecodable report")
        } catch let error as UsageError {
            guard case .parseFailed(let message) = error else {
                Issue.record("Expected parseFailed, got \(error)")
                return
            }
            #expect(message.hasPrefix("Malformed omp usage JSON"))
        }
    }

    @Test
    func `should show no data when no account is signed in`() {
        #expect(throws: UsageError.noData) {
            try OmpFixtures.parse("{ \"reports\": [] }")
        }
    }
}
