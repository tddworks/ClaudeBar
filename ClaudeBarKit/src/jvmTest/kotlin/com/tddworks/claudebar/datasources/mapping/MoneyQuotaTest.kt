package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource

/**
 * A JSON mapping can read money — "$12.40 remaining", "of $50.00" — and a balance with no
 * ceiling reads as money with no percentage (Add Provider's "never — a balance").
 */
class MoneyQuotaTest {
    private val dollar = 1_000_000_000L

    private fun usage(mapping: String, body: String): UsageSnapshot =
        Mapping.from(Json.parseToJsonElement("""{ "json": $mapping }""")).reader({ null }, NoScriptEngine, { 0.0 })
            .read(Response(status = 200, body = body.encodeToByteArray()), MappingFacts(), "openrouter")

    private val balance = """{ "quotas": [{ "kind": "model", "name": "Balance", "left": { "money": "$.balance", "currency": "USD" } }] }"""

    @ParameterizedTest
    @CsvSource("0.123456789, 123456789", "1245.67, 1245670000000", "-1.25, -1250000000", "1e2, 100000000000")
    fun `should show money the answer sends as text exactly`(amount: String, nanos: Long) {
        val usage = usage(balance, """{"balance":"$amount"}""")
        assertEquals(Left.Balance(Money(nanos, "USD"), null), usage.quotas.first().left)
    }

    @ParameterizedTest
    @ValueSource(strings = ["0x10", "12abc", "", "NaN"])
    fun `should show no quota when the money text isn't a decimal amount`(text: String) {
        val usage = usage(balance, """{"balance":"$text"}""")
        assertTrue(usage.quotas.isEmpty())
    }

    @Test
    fun `should show money left out of its limit with the percentage left`() {
        val usage = usage(
            """
            { "quotas": [{ "kind": "time", "name": "Credits",
                           "left": { "money": "$.data.limit_remaining", "of": "$.data.limit", "currency": "USD" } }] }
            """,
            """{"data":{"limit_remaining":12.4,"limit":50}}""",
        )

        val credits = usage.quotas.single()
        assertEquals(Left.Balance(Money(12_400_000_000, "USD"), Money(50 * dollar, "USD")), credits.left)
        assertEquals(24.8, credits.percentLeft)
    }

    @Test
    fun `should show a balance with no percentage and no window`() {
        val usage = usage("""{ "quotas": [{ "kind": "time", "name": "Balance", "left": { "money": "$.balance" } }] }""", """{"balance":7.5}""")

        val balance = usage.quotas.single()
        assertTrue(balance.isBalance)
        assertNull(balance.percentLeft)
        assertNull(balance.window)
    }
}
