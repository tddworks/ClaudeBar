package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import kotlin.math.abs

/** `omp usage --json` read by `omp-usage.js`, through Oh My Pi's definition. */
private object OmpFixtures {
    fun parse(text: String): UsageSnapshot {
        val definition = TestDefinitions.builtIn("omp")
        val source = testDataSources().make(definition.dataSources[0], "omp", scripts = TestDefinitions.builtIns::script)
        try {
            return source.read(Response(text))
        } catch (error: DataSourceError) {
            throw error.reason
        }
    }

    /** The name a provider id is shown with, read through a one-limit report. */
    fun displayName(id: String): String? {
        val snapshot = parse("""{"reports":[{"provider":"$id","limits":[{"scope":{"windowId":"5h"},"amount":{"remainingFraction":0.5}}]}]}""")
        return snapshot.quotas.firstOrNull()?.group
    }
}

private fun parse(text: String) = OmpFixtures.parse(text)

private fun displayName(id: String) = OmpFixtures.displayName(id)

private fun <T> required(value: T?): T {
    assertNotNull(value)
    return value!!
}

private fun dollars(amount: String): Long = java.math.BigDecimal(amount).movePointRight(9).longValueExact()

/**
 * The old probe's fixtures, quota for quota. Card and menu-bar titles are the page's, not the
 * usage's, so they are no longer checked here.
 */
class OmpDefinitionTest {

    /**
     * Representative fixture modeled on real `omp usage --json` output (omp v16.4.6): three
     * upstream providers, tiered sub-limits, and a limit without a reset timestamp. All
     * identifiers are synthetic.
     */
    private val SAMPLE_RESPONSE = """
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

    // Quota Mapping

    @Test
    fun `should show a quota for every limit omp reports, all as Oh My Pi's`() {
        val snapshot = parse(SAMPLE_RESPONSE)

        assertEquals("omp", snapshot.providerId)
        assertEquals(7, snapshot.quotas.size)
        assertTrue(snapshot.quotas.all { it.providerId == "omp" })
    }

    @Test
    fun `should show the percent left that omp reports as a fraction`() {
        val snapshot = parse(SAMPLE_RESPONSE)

        assertEquals(92.0, snapshot.quota(QuotaType.TimeLimit("Claude 5h"))?.percentRemaining)
        assertEquals(42.0, snapshot.quota(QuotaType.TimeLimit("Codex 7d"))?.percentRemaining)
        // Fraction-only amounts (no used/limit pair) still map
        assertEquals(75.0, snapshot.quota(QuotaType.TimeLimit("Z.ai 5h"))?.percentRemaining)
    }

    @Test
    fun `should name each quota by its provider, tier and window`() {
        val snapshot = parse(SAMPLE_RESPONSE)
        val labels = snapshot.quotas.map { it.quotaType.displayName }

        assertTrue(labels.contains("Claude 5h"))
        assertTrue(labels.contains("Claude Fable 7d"))
        assertTrue(labels.contains("Codex Spark 5h"))
        assertTrue(labels.contains("Z.ai 1mo"))
    }

    @Test
    fun `should show the reset time omp gives in epoch milliseconds`() {
        val snapshot = parse(SAMPLE_RESPONSE)
        val claude = required(snapshot.quota(QuotaType.TimeLimit("Claude 5h")))

        assertEquals(1_783_885_200.0, claude.resetsAtSeconds)
    }

    @Test
    fun `should keep each limit's window length so pace can be shown`() {
        val snapshot = parse(SAMPLE_RESPONSE)

        assertEquals(18_000.0, snapshot.quota(QuotaType.TimeLimit("Claude 5h"))?.windowSeconds)
        assertEquals(604_800.0, snapshot.quota(QuotaType.TimeLimit("Codex 7d"))?.windowSeconds)
    }

    @Test
    fun `should show no reset when a limit has no reset time`() {
        val snapshot = parse(SAMPLE_RESPONSE)
        val zai = required(snapshot.quota(QuotaType.TimeLimit("Z.ai 5h")))

        assertNull(zai.resetsAtSeconds)
    }

    // Monetary Limits

    @Test
    fun `should show a capped spend limit with nothing spent as a full dollar quota in its provider's group`() {
        val json = """
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

        val snapshot = parse(json)
        val quota = required(snapshot.quota(QuotaType.TimeLimit("Claude Extra")))

        assertEquals(100.0, quota.percentRemaining)
        assertEquals(dollars("0"), quota.dollarUsedNanos)
        assertEquals(dollars("500"), quota.dollarCapNanos)
        assertEquals("Claude", quota.group)
    }

    @Test
    fun `should show a capped spend limit as dollars left of its cap, in rounded dollars`() {
        val json = """
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

        val snapshot = parse(json)
        val quota = required(snapshot.quota(QuotaType.TimeLimit("Claude Extra")))

        // Money left of its cap is the measure (the Left law): $376.55 of $500,
        // whatever fraction omp reports beside it.
        assertEquals(Left.Balance(Money(dollars("376.55"), "USD"), Money(dollars("500"), "USD")), quota.left)
        assertEquals(dollars("123.45"), quota.dollarUsedNanos)
        assertEquals(dollars("500"), quota.dollarCapNanos)
    }

    @Test
    fun `should round spend to the cent exactly when it sits on a cent boundary`() {
        // Decimal decodes straight from the JSON number token: 1.005 rounds
        // to $1.01. A Double round-trip would decode 1.00499… and show $1.00.
        val json = """
        { "reports": [ {
            "provider": "anthropic",
            "limits": [ {
              "scope": { "windowId": "extra" },
              "amount": { "used": 1.005, "limit": 1.25e1, "unit": "usd" }
            } ]
        } ] }
        """

        val snapshot = parse(json)
        val quota = required(snapshot.quota(QuotaType.TimeLimit("Claude Extra")))

        assertEquals(dollars("1.01"), quota.dollarUsedNanos)
        assertEquals(dollars("12.5"), quota.dollarCapNanos)
        // The share follows the cents shown: (12.50 - 1.01) / 12.50.
        val percent = required(quota.percentRemaining)
        assertTrue(abs(percent - 91.92) < 0.0001)
    }

    @Test
    fun `should name a spend limit after its window when omp gives it no label`() {
        val json = """
        { "reports": [ {
            "provider": "opencode-go",
            "limits": [ {
              "window": { "id": "monthly" },
              "amount": { "used": 50, "limit": 500, "unit": "usd" }
            } ]
        } ] }
        """

        val snapshot = parse(json)
        val quota = required(snapshot.quota(QuotaType.TimeLimit("OpenCode Go Monthly")))
        assertEquals(dollars("50"), quota.dollarUsedNanos)
        assertEquals(dollars("500"), quota.dollarCapNanos)
    }

    @Test
    fun `should show uncapped spend as a note in its provider's group, not a quota`() {
        val json = """
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

        val snapshot = parse(json)

        assertTrue(snapshot.quotas.isEmpty())
        val metrics = required(snapshot.extensionMetrics)
        assertEquals(1, metrics.size)
        assertEquals("Claude Extra Usage", metrics[0].label)
        assertEquals("Extra usage $1,234.56 spent · no cap", metrics[0].value)
        assertEquals("Claude", metrics[0].group)
        assertEquals("Extra usage $1,234.56 spent · no cap", snapshot.quotaGroups.firstOrNull()?.note)
    }

    @Test
    fun `should name Cursor's windowless spend limits Spend, never USD`() {
        val json = """
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

        val snapshot = parse(json)
        val labels = snapshot.quotas.map { it.quotaType.displayName }

        assertEquals(listOf("Cursor Spend", "Cursor Spend (2)"), labels)
        assertTrue(labels.all { !it.contains("usd", ignoreCase = true) })
        assertEquals(dollars("1234.56"), snapshot.quotas.firstOrNull()?.dollarUsedNanos)
        assertEquals(dollars("5000"), snapshot.quotas.firstOrNull()?.dollarCapNanos)
    }

    @Test
    fun `should show a spend limit and a window limit of one account in one group`() {
        val json = """
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

        val snapshot = parse(json)

        assertEquals(listOf("Claude 5h", "Claude Extra"), snapshot.quotas.map { it.quotaType.displayName })
        assertTrue(snapshot.quotas.all { it.group == "Claude" })
        assertEquals(1, snapshot.quotaGroups.size)
        assertEquals(2, snapshot.quotaGroups[0].quotas.size)
    }

    @Test
    fun `should tell apart the uncapped spend notes of two accounts on one provider`() {
        val json = """
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

        val snapshot = parse(json)
        val metrics = required(snapshot.extensionMetrics)

        assertTrue(snapshot.quotas.isEmpty())
        assertEquals(
            listOf(
                "Claude Extra Usage · work",
                "Claude Extra Usage · home",
            ),
            metrics.map { it.label },
        )
        assertEquals(listOf("Claude · work", "Claude · home"), metrics.map { it.group })
        assertEquals(metrics.size, metrics.map { it.label }.toSet().size)
    }

    // Account Email

    @Test
    fun `should show no email when the accounts have different emails`() {
        val snapshot = parse(SAMPLE_RESPONSE)

        assertNull(snapshot.accountEmail)
    }

    @Test
    fun `should show the email when there is a single account`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals("solo@example.com", snapshot.accountEmail)
    }

    // Multiple Accounts on One Provider

    @Test
    fun `should tell apart two accounts on the same provider, each quota unique`() {
        val json = """
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
        val snapshot = parse(json)
        val labels = snapshot.quotas.map { it.quotaType.displayName }

        assertTrue(labels.contains("Claude 5h · work"))
        assertTrue(labels.contains("Claude 5h · home"))
        // Quota keys are persisted and used as stable UI identifiers —
        // they must never collide across accounts.
        val keys = snapshot.quotas.map { it.quotaType.quotaKey }.toSet()
        assertEquals(snapshot.quotas.size, keys.size)
    }

    @Test
    fun `should tell apart two meters sharing one window by what they meter`() {
        // Z.ai can meter tokens and requests over the same window; both
        // must stay distinguishable without degrading to bare ordinals.
        val json = """
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
        val snapshot = parse(json)
        val labels = snapshot.quotas.map { it.quotaType.displayName }

        assertTrue(labels.contains("Z.ai Tokens 5h"))
        assertTrue(labels.contains("Z.ai Requests 5h"))
        assertTrue(!labels.any { it.endsWith("(2)") })
    }

    // Card Title Humanization

    /// Modeled on live `omp usage --json` output for `kimi-code` (omp
    /// v17.0.2): the reporter emits machine window ids alongside human
    /// labels. All values are synthetic.
    private val KIMI_RESPONSE = """
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

    // Accounts Without Usage

    @Test
    fun `should show no account rows when every account reported usage`() {
        val snapshot = parse(SAMPLE_RESPONSE)

        assertNull(snapshot.extensionMetrics)
    }

    @Test
    fun `should show the quotas and a no-usage row for an account that reported none`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        val metrics = required(snapshot.extensionMetrics)
        assertEquals(1, metrics.size)
        assertEquals("Copilot · work@example.com", metrics[0].label)
        assertEquals("No usage reported", metrics[0].value)
    }

    @Test
    fun `should show a no-usage row for each account, not no data, when none reported usage`() {
        val json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "solo@example.com" },
            { "provider": "openai-codex", "type": "api_key" }
          ] }
        """
        val snapshot = parse(json)

        assertTrue(snapshot.quotas.isEmpty())
        val metrics = required(snapshot.extensionMetrics)
        assertEquals(listOf("Claude · solo@example.com", "Codex · API key"), metrics.map { it.label })
        assertTrue(metrics.all { it.value == "No usage reported" })
    }

    @Test
    fun `should give each anonymous account on one provider its own row name`() {
        // MenuContentView keys these cards by label — collisions would
        // hide or reuse rows.
        val json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "openai-codex", "type": "api_key" },
            { "provider": "openai-codex", "type": "api_key" }
          ] }
        """
        val snapshot = parse(json)
        val labels = required(snapshot.extensionMetrics).map { it.label }

        assertEquals(listOf("Codex · API key", "Codex · API key (2)"), labels)
        assertEquals(labels.size, labels.toSet().size)
    }

    @Test
    fun `should show the email of the single account even when it reported no usage`() {
        val json = """
        { "reports": [],
          "accountsWithoutUsage": [
            { "provider": "anthropic", "type": "oauth", "email": "solo@example.com" }
          ] }
        """
        val snapshot = parse(json)

        assertEquals("solo@example.com", snapshot.accountEmail)
    }

    @Test
    fun `should show no no-usage row for an account that also reported usage under the same account id`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertNull(snapshot.extensionMetrics)
    }

    @Test
    fun `should show no no-usage row for an account whose id a limit already reported`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertNull(snapshot.extensionMetrics)
    }

    @Test
    fun `should show the no-usage row when the same account id reported usage on another provider`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Copilot · shared-account-id"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show no no-usage row when the same email, in any case or spacing, reported usage`() {
        val json = """
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
        val snapshot = parse(json)

        assertNull(snapshot.extensionMetrics)
    }

    @Test
    fun `should show no no-usage row when the same email reported usage under another credential`() {
        val json = """
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
        val snapshot = parse(json)

        assertNull(snapshot.extensionMetrics)
    }

    @Test
    fun `should show the no-usage row when the same email reported usage for another organization`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Claude · alice@example.com"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show the no-usage row when omp reports it even for the same email and organization`() {
        // omp's org gate normally absorbs this identity into the same-org
        // report. If it still reaches ClaudeBar, preserve omp's decision to
        // surface the failed fetch instead of second-guessing it by email.
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Claude · alice@example.com"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show the no-usage row when the matching account id belongs to an organization`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Claude · shared-account-id"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show the no-usage row when the same email reported usage on another provider`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Copilot · shared@example.com"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show both a reported account and an unreported one on the same provider`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        assertEquals(listOf("Claude · bob@example.com"), snapshot.extensionMetrics?.map { it.label })
        assertEquals(listOf("Claude", "Claude · bob"), snapshot.quotaGroups.map { it.title })
    }

    @Test
    fun `should show the no-usage row when the emails differ even though the account id matches`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Claude · bob@example.com"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show the no-usage row when only a project id is shared`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Gemini · shared-project"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show two rows for blank-email accounts with different account ids`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(2, snapshot.extensionMetrics?.size)
    }

    @Test
    fun `should show one row for blank-email accounts with the same account id`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.extensionMetrics?.size)
    }

    @Test
    fun `should show one row for unreported accounts with the same email`() {
        val json = """
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
        val snapshot = parse(json)
        val metrics = required(snapshot.extensionMetrics)

        assertEquals(1, metrics.size)
        assertEquals("Claude · alice@example.com", metrics[0].label)
    }

    @Test
    fun `should show a row for each organization when one email has two`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(2, snapshot.extensionMetrics?.size)
    }

    @Test
    fun `should show an organization account and a legacy one with the same email as two rows, in either order`() {
        val organizationFirst = """
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
        val legacyFirst = """
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

        val organizationFirstSnapshot = parse(organizationFirst)
        val legacyFirstSnapshot = parse(legacyFirst)

        assertEquals(2, organizationFirstSnapshot.extensionMetrics?.size)
        assertEquals(2, legacyFirstSnapshot.extensionMetrics?.size)
    }

    @Test
    fun `should show one row when an account with no limits is also listed as unreported`() {
        val json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": [],
            "metadata": { "email": "local@ollama.dev" }
        } ],
          "accountsWithoutUsage": [
            { "provider": "ollama", "type": "oauth", "email": "LOCAL@OLLAMA.DEV" }
          ] }
        """
        val snapshot = parse(json)

        assertEquals(listOf("Ollama · local@ollama.dev"), snapshot.extensionMetrics?.map { it.label })
        assertEquals(listOf("Ollama · local"), snapshot.quotaGroups.map { it.title })
    }

    @Test
    fun `should show an anonymous unreported account apart from an anonymous report`() {
        val json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": []
        } ],
          "accountsWithoutUsage": [
            { "provider": "ollama", "type": "oauth" }
          ] }
        """
        val snapshot = parse(json)

        assertEquals(
            listOf(
                "Ollama · account 1",
                "Ollama · OAuth account",
            ),
            snapshot.extensionMetrics?.map { it.label },
        )
    }

    @Test
    fun `should show one group per account and no stale rows when each account reported under a new credential`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(2, snapshot.quotas.size)
        assertEquals(listOf("Claude · alice", "Claude · bob"), snapshot.quotaGroups.map { it.title })
        assertNull(snapshot.extensionMetrics)
    }

    // Reports Without Usable Limits

    @Test
    fun `should still list an account whose report has no limits`() {
        // Ollama's usage provider deliberately reports `limits: []` (no
        // standalone quota API); a report exists, so the account never
        // appears in accountsWithoutUsage — it must not vanish here.
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
        val metrics = required(snapshot.extensionMetrics)
        assertEquals(listOf("Ollama · local@ollama.dev"), metrics.map { it.label })
        assertEquals("No usage reported", metrics[0].value)
    }

    @Test
    fun `should show account rows, not no data, when every report has no limits`() {
        val json = """
        { "reports": [ { "provider": "ollama", "limits": [] } ] }
        """
        val snapshot = parse(json)

        assertTrue(snapshot.quotas.isEmpty())
        assertEquals(listOf("Ollama · account 1"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should name an account after its limits when its report carries no identity`() {
        // Gemini/Kimi-style reports carry identity in limit scopes rather
        // than metadata; a report whose limits are all unusable must still
        // be attributed via that scope.
        val json = """
        { "reports": [ {
            "provider": "google-gemini-cli",
            "limits": [ {
              "scope": { "windowId": "1d", "projectId": "my-gcp-project" },
              "window": { "id": "1d" }
            } ]
        } ] }
        """
        val snapshot = parse(json)

        assertEquals(listOf("Gemini · my-gcp-project"), snapshot.extensionMetrics?.map { it.label })
    }

    @Test
    fun `should show anonymous accounts with no limits on one provider as numbered sections`() {
        val json = """
        { "reports": [
            { "provider": "ollama", "limits": [] },
            { "provider": "ollama", "limits": [] }
        ] }
        """
        val snapshot = parse(json)
        val labels = required(snapshot.extensionMetrics).map { it.label }

        assertEquals(listOf("Ollama · #1", "Ollama · #2"), labels)
        assertEquals(labels.size, labels.toSet().size)
        // Section titles stay clean per account — no bogus "(2)" suffixes
        // from quota-group reservations that never emitted quotas.
        val snapshot2 = parse(json)
        assertEquals(listOf("Ollama · #1", "Ollama · #2"), snapshot2.extensionMetrics?.map { it.group })
        assertEquals(true, snapshot2.hasQuotaGroups)
        assertEquals(listOf("Ollama · #1", "Ollama · #2"), snapshot2.quotaGroups.map { it.title })
    }

    // Grouping Metadata

    @Test
    fun `should group quotas into one section per provider, in the order omp reports them`() {
        val snapshot = parse(SAMPLE_RESPONSE)

        val claude5h = required(snapshot.quota(QuotaType.TimeLimit("Claude 5h")))
        assertEquals("Claude", claude5h.group)

        val spark = required(snapshot.quota(QuotaType.TimeLimit("Codex Spark 5h")))
        assertEquals("Codex", spark.group)

        val fable = required(snapshot.quota(QuotaType.TimeLimit("Claude Fable 7d")))

        // Three upstream providers → three sections, in payload order.
        assertEquals(listOf("Codex", "Claude", "Z.ai"), snapshot.quotaGroups.map { it.title })
    }

    @Test
    fun `should show a section per account when one provider has two`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(listOf("Claude · work", "Claude · home"), snapshot.quotaGroups.map { it.title })
        // Card titles inside a section drop the account context entirely.
    }

    @Test
    fun `should show no-usage accounts as their own sections, named by short identities`() {
        val json = """
        { "reports": [ {
            "provider": "ollama",
            "limits": [],
            "metadata": { "email": "local@ollama.dev" }
        } ],
          "accountsWithoutUsage": [
            { "provider": "github-copilot", "type": "oauth", "email": "work@example.com" }
          ] }
        """
        val snapshot = parse(json)
        val metrics = required(snapshot.extensionMetrics)

        assertEquals(listOf("Ollama · local", "Copilot · work"), metrics.map { it.group })
        // Sections carry the note inline; no quota cards exist.
        val groups = snapshot.quotaGroups
        assertEquals(listOf("Ollama · local", "Copilot · work"), groups.map { it.title })
        assertTrue(groups.all { it.quotas.isEmpty() && it.note == "No usage reported" })
    }

    // Upstream Display Names

    // Every id omp v16.4.6's usage registry emits (@oh-my-pi/pi-ai/src/usage/*).
    @ParameterizedTest
    @CsvSource(
        "anthropic, Claude",
        "openai-codex, Codex",
        "zai, Z.ai",
        "google-gemini-cli, Gemini",
        "google-antigravity, Antigravity",
        "github-copilot, Copilot",
        "kimi-code, Kimi",
        "minimax-code, MiniMax",
        "minimax-code-cn, MiniMax CN",
        "opencode-go, OpenCode Go",
        "ollama, Ollama",
        "ollama-cloud, Ollama Cloud",
    )
    fun `should show every provider omp reports by its display name`(id: String, expected: String) {
        assertEquals(expected, displayName(id))
    }

    // Robustness

    @Test
    fun `should read the usage when omp prints other lines around it`() {
        val noisy = "Synced 3 accounts\n$SAMPLE_RESPONSE\nDone."
        val snapshot = parse(noisy)

        assertEquals(7, snapshot.quotas.size)
    }

    @Test
    fun `should skip a limit with no usable amount`() {
        val json = """
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
        val snapshot = parse(json)

        assertEquals(1, snapshot.quotas.size)
    }

    @Test
    fun `should fail to read usage when omp prints something that is not usage`() {
        // Pin the exact error so a regression to `noData` (or any other
        // case) fails instead of passing as "some UsageError".
        assertEquals(
            UsageError.ParseFailed("No JSON object in omp usage output"),
            assertThrows(UsageError::class.java) { parse("not json at all") },
        )

        // A JSON object whose reports can't decode (missing `provider`)
        // is a decode failure - parseFailed, never an empty-pool noData.
        val error = assertThrows(UsageError::class.java) { parse("{ \"reports\": [ { } ] }") }
        assertTrue(error is UsageError.ParseFailed, "Expected parseFailed, got $error")
        assertTrue((error as UsageError.ParseFailed).reason.startsWith("Malformed omp usage JSON"))
    }

    @Test
    fun `should show no data when no account is signed in`() {
        assertEquals(UsageError.NoData, assertThrows(UsageError::class.java) { parse("{ \"reports\": [] }") })
    }
}

