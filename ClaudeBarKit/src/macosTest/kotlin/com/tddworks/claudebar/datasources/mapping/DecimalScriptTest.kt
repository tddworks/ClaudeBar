package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.Money
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlin.test.Test
import kotlin.test.assertEquals

/** `jsonDecimal` and `decimalCents` — money a script reads stays exact, in JavaScriptCore. */
class DecimalScriptTest {
    private fun read(body: String, script: String): UsageSnapshot =
        Mapping.Script(ScriptMapping("money.js")).reader({ script }, JavaScriptCoreEngine(), { 0.0 })
            .read(Response(body), MappingFacts(), "acme")

    private fun money(script: String) = read("{}", script).quotas.first().left

    @Test
    fun `should show a balance with every digit the answer gave`() {
        val usage = read(
            """{"balance": 0.1000000000000000055511151231257827}""",
            """
            function read(response) {
              var balance = jsonDecimal(response.text).balance;
              return { quotas: [{ type: 'model', name: 'Balance', left: { money: balance, currency: 'USD' } }] };
            }
            """,
        )
        // Nano-units keep nine places; the tenth rounds.
        assertEquals(Left.Balance(Money(100_000_000, "USD"), null), usage.quotas.first().left)
    }

    @Test
    fun `should round money to the cent half up without losing precision`() {
        for ((amount, nanos) in listOf("12.345" to 12_350_000_000L, "12.344" to 12_340_000_000L, "-0.004" to 0L, "1e2" to 100_000_000_000L, "99.995" to 100_000_000_000L)) {
            val left = money(
                """
                function read() {
                  return { quotas: [{ type: 'model', name: 'Balance', left: { money: decimalCents('$amount'), currency: 'USD' } }] };
                }
                """,
            )
            assertEquals(Left.Balance(Money(nanos, "USD"), null), left, amount)
        }
    }

    @Test
    fun `should multiply money exactly`() {
        for ((pair, nanos) in listOf(("1234567" to "0.000003") to 3_703_701_000L, ("0.1" to "0.2") to 20_000_000L,
            ("-2.5" to "4") to -10_000_000_000L, ("1e6" to "1.5") to 1_500_000_000_000_000L)) {
            val left = money(
                """
                function read() {
                  return { quotas: [{ type: 'model', name: 'Cost', left: { money: decimalMultiply('${pair.first}', '${pair.second}'), currency: 'USD' } }] };
                }
                """,
            )
            assertEquals(Left.Balance(Money(nanos, "USD"), null), left, "$pair")
        }
    }

    @Test
    fun `should add money exactly`() {
        for ((pair, nanos) in listOf(("0.1" to "0.2") to 300_000_000L, ("1.005" to "-0.005") to 1_000_000_000L, ("12" to "0.000001") to 12_000_001_000L)) {
            val left = money(
                """
                function read() {
                  return { quotas: [{ type: 'model', name: 'Cost', left: { money: decimalAdd('${pair.first}', '${pair.second}'), currency: 'USD' } }] };
                }
                """,
            )
            assertEquals(Left.Balance(Money(nanos, "USD"), null), left, "$pair")
        }
    }
}
