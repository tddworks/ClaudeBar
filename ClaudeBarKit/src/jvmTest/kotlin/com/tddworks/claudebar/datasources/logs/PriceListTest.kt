package com.tddworks.claudebar.datasources.logs

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** A price file is data: a model is priced by the first rule that knows it, and money stays exact. */
class PriceListTest {
    companion object {
        val file = """
        {
          "per": 1000000,
          "models": [
            { "id": "m-large-2", "input": "5", "output": "25", "cacheWrite": "6.25", "cacheWrite1h": "10", "cacheRead": "0.50" },
            { "id": "m-medium-2", "input": "3", "output": "15", "cacheWrite": "3.75", "cacheRead": "0.30" },
            { "id": "m-small-1", "input": "1", "output": "5", "cacheWrite": "1.25", "cacheRead": "0.10" }
          ],
          "families": [ { "contains": "large", "as": "m-large-2" }, { "contains": "small", "as": "m-small-1" } ],
          "free": [ "llama", "qwen" ],
          "otherwise": { "input": "3", "output": "15", "cacheWrite": "3.75", "cacheRead": "0.30" }
        }
        """.trimIndent()

        internal fun usd(text: String) = NanoAmount.parse(text)!!
    }

    private val prices = PriceList.load("prices.json") { file }!!

    /** 1M in, 100K out, 1M cache write, 1M cache read. */
    private fun record(model: String) =
        LogRecord(atSeconds = 0.0, model = model, input = 1_000_000, output = 100_000, cacheWrite = 1_000_000, cacheRead = 1_000_000)

    @Test
    fun `should price a model listed by its exact name at its own price`() {
        val price = prices.price("m-medium-2")
        assertEquals(listOf(usd("3"), usd("15"), usd("3.75"), usd("0.30")), listOf(price.input, price.output, price.cacheWrite, price.cacheRead))
    }

    @Test
    fun `should price a dated model like the listed model its name starts with`() {
        assertEquals(usd("3"), prices.price("m-medium-2-20260101").input)
    }

    @Test
    fun `should price an unlisted model by the family its name belongs to`() {
        assertEquals(usd("5"), prices.price("m-large-99-20260101").input)
    }

    @Test
    fun `should price an unknown model at the fallback price, never at nothing`() {
        assertEquals(usd("3"), prices.price("acme-unknown").input)
    }

    @Test
    fun `should cost and save nothing for a free model, whatever its size tag`() {
        assertEquals(NanoAmount.ZERO, prices.cost(record("qwen3-coder:30b")))
        assertEquals(NanoAmount.ZERO, prices.savings(record("llama-3.3-70b")))
    }

    @Test
    fun `should cost nothing for an unlisted model served on this Mac`() {
        assertEquals(NanoAmount.ZERO, prices.cost(record("acme-internal-7b"), servedLocally = true))
    }

    @Test
    fun `should keep a listed model's price and savings when served on this Mac`() {
        assertEquals(usd("8.55"), prices.cost(record("m-medium-2"), servedLocally = true))
        assertEquals(usd("2.7"), prices.savings(record("m-medium-2"), servedLocally = true))
    }

    @Test
    fun `should cost every kind of token at its own price, exactly`() {
        val plain = LogRecord(atSeconds = 0.0, model = "m-medium-2", input = 1_000_000, output = 100_000)
        val cached = LogRecord(atSeconds = 0.0, model = "m-medium-2", cacheWrite = 1_000_000, cacheRead = 1_000_000)
        assertEquals(usd("4.5"), prices.cost(plain))
        assertEquals(usd("4.05"), prices.cost(cached))
    }

    @Test
    fun `should save what cache reads would have cost as input, less what they cost`() {
        assertEquals(usd("9"), prices.savings(LogRecord(atSeconds = 0.0, model = "m-large-2", cacheRead = 2_000_000)))
        assertEquals(NanoAmount.ZERO, prices.savings(LogRecord(atSeconds = 0.0, model = "m-large-2", input = 1_000_000)))
    }

    @Test
    fun `should price hour-long cache writes at the hour price and the rest at the five-minute price`() {
        val writes = LogRecord(atSeconds = 0.0, model = "m-large-2", cacheWrite = 1_000_000, cacheWrite1h = 600_000)
        // 0.4M × $6.25 + 0.6M × $10.
        assertEquals(usd("8.5"), prices.cost(writes))
    }

    @Test
    fun `should price every cache write at the five-minute price when the model has no hour price`() {
        val writes = LogRecord(atSeconds = 0.0, model = "m-medium-2", cacheWrite = 1_000_000, cacheWrite1h = 600_000)
        assertEquals(usd("3.75"), prices.cost(writes))
    }

    @Test
    fun `should have no price list when its file is missing or broken`() {
        assertNull(PriceList.load("prices.json") { null })
        assertNull(PriceList.load("prices.json") { "{" })
    }

    // Beyond the Swift suite: what Decimal gave for free, nanos must keep.

    @Test
    fun `should keep a fraction of a nano until the day is summed`() {
        // $0.000075 per million tokens: one token costs 0.075 of a nano.
        val cheap = PriceList.from(kotlinx.serialization.json.Json.parseToJsonElement(
            """{ "per": 1000000, "otherwise": { "input": "0.000075", "output": "0", "cacheWrite": "0", "cacheRead": "0" } }""",
        ))
        val one = cheap.cost(LogRecord(atSeconds = 0.0, input = 1))
        val sum = (1..20).fold(NanoAmount.ZERO) { total, _ -> total + one }
        assertEquals(0L, one.rounded())
        assertEquals(2L, sum.rounded()) // 1.5 nanos rounds away from zero
    }

    @Test
    fun `should read an amount written as text, as a number, or with an exponent exactly`() {
        assertEquals(NanoAmount(12_300_000), NanoAmount.parse("0.0123"))
        assertEquals(NanoAmount(10_000), NanoAmount.parse("1e-5"))
        assertEquals(NanoAmount(0, 500_000_000), NanoAmount.parse("0.0000000005"))
        assertEquals(NanoAmount(-1_500_000_000), NanoAmount.parse("-1.5"))
        assertNull(NanoAmount.parse("lots"))
    }
}
