package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.DateRange
import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.datasources.logs.localCalendar
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * *TODAY'S USAGE* — what a login used, day by day, read from its tool's own logs. The login
 * owns it: `account.usageHistory`, null when the provider offers none or the login's logs aren't read.
 */
class UsageHistoryTest {
    private val stub = StubbedProvider()
    private val home = stub.home
    private val calendar = localCalendar()
    private val now = System.currentTimeMillis() / 1000.0

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private val acme = UsageLog.Definition(
        records = UsageLog.Records(files = "~/.acme/*.jsonl", at = UsageLog.At.Field("$.at"), tokens = UsageLog.Tokens(total = "$.tokens"), cost = "$.cost"),
    )

    private fun makeLog(definition: UsageLog.Definition) = UsageLog.make(definition, home, { null }, now = { System.currentTimeMillis() / 1000.0 })

    private fun history() = UsageHistory(makeLog(acme))

    private fun daysAgo(days: Int) = calendar.addingDays(-days, calendar.startOfDay(now))

    private fun log(vararg entries: Pair<String, Int>) {
        val dir = File(home, ".acme").also { it.mkdirs() }
        val lines = entries.map { (cost, ago) ->
            val at = if (ago == 0) now else daysAgo(ago) + 43_200
            """{"at":$at,"tokens":1000,"cost":$cost}"""
        }
        File(dir, "log.jsonl").writeText(lines.joinToString("\n"))
    }

    private fun dollars(amount: Long) = amount * 1_000_000_000

    private fun login(id: String) = ProviderAccountConfig(id, "", null, probeConfig = mapOf("directory" to "/tmp/$id"))

    // Reading

    @Test
    fun `should show today's usage against yesterday's`() = runBlocking {
        log("14" to 0, "41" to 1)
        val history = history()

        history.read()

        assertEquals(dollars(14), history.report?.today?.totalCostNanos)
        assertEquals(dollars(41), history.report?.previous?.totalCostNanos)
    }

    @Test
    fun `should show no usage history when nothing was used today or yesterday`() = runBlocking {
        val history = history()

        history.read()

        assertNull(history.report)
    }

    @Test
    fun `should show yesterday's usage and an empty today when only yesterday was used`() = runBlocking {
        log("41" to 1)
        val history = history()

        history.read()

        assertEquals(dollars(41), history.report?.previous?.totalCostNanos)
        assertEquals(true, history.report?.today?.isEmpty)
    }

    @Test
    fun `should chart the last thirty days, oldest first, leaving out older days`() = runBlocking {
        log("14" to 0, "41" to 1, "7" to 29, "99" to 30)
        val history = history()

        history.read()

        assertEquals(30, history.lastThirtyDays.size)
        assertEquals(dollars(7), history.lastThirtyDays.first().totalCostNanos)
        assertEquals(listOf(dollars(41), dollars(14)), history.lastThirtyDays.takeLast(2).map { it.totalCostNanos })
    }

    @Test
    fun `should show no chart when nothing was used in thirty days`() = runBlocking {
        val history = history()

        history.read()

        assertTrue(history.lastThirtyDays.isEmpty())
    }

    @Test
    fun `should show every day of a range, used or not`() = runBlocking {
        log("14" to 0, "41" to 1)

        val days = history().days(DateRange.last(30, now, calendar))

        assertEquals(30, days.size)
        assertEquals(listOf(dollars(41), dollars(14)), days.map { it.totalCostNanos }.takeLast(2))
    }

    // The login owns it

    @Test
    fun `should give the default login the provider's usage history`() {
        val history = history()
        val provider = stub.makeProvider("grok", usageHistory = history)

        assertSame(history, provider.defaultAccount.usageHistory)
    }

    @Test
    fun `should show no usage history for an added login whose logs are not read`() {
        val provider = stub.makeProvider("grok", accounts = listOf(login("work")), usageHistory = history())

        assertNull(provider.accounts.all.first { !it.isDefault }.usageHistory)
    }

    @Test
    fun `should show no usage history when the provider offers none`() {
        val provider = stub.makeProvider("grok")

        assertNull(provider.defaultAccount.usageHistory)
    }

    // Other apps

    private fun desk(tokens: Int, daysAgo: Int = 0) {
        val dir = File(home, "Desk").also { it.mkdirs() }
        val at = if (daysAgo == 0) now else now - daysAgo * 86_400.0
        File(dir, "today.json").writeText("""{"at":$at,"n":$tokens}""")
    }

    private val deskDefinition = acme.copy(
        otherApps = listOf(
            UsageLog.OtherApp(
                label = "Desk",
                records = UsageLog.Records(files = "~/Desk/today.json", format = UsageLog.Format.JSON, at = UsageLog.At.Field("$.at"), tokens = UsageLog.Tokens(total = "$.n")),
            ),
        ),
    )

    private fun historyWithDesk(ledger: (String) -> DayLedger? = { null }) = UsageHistory(deskDefinition, "acme", ::makeLog, ledger)

    @Test
    fun `should show each other app's usage under its own name, apart from the login's`() = runBlocking {
        log("14" to 0)
        desk(74_422)
        val history = historyWithDesk()

        history.read()

        val desk = history.otherApps.first()
        assertEquals("Desk", desk.label)
        assertEquals(74_422L, desk.report?.today?.totalTokens)
        assertFalse(desk.knowsCost)
        assertEquals(listOf("Desk"), history.usedOtherApps.map { it.label })
        assertTrue(history.hasUsage)
        assertNull(history.label)
        assertEquals(1000L, history.report?.today?.totalTokens)
    }

    @Test
    fun `should have usage to show when only another app was used`() = runBlocking {
        desk(74_422)
        val history = historyWithDesk()

        history.read()

        assertNull(history.report)
        assertTrue(history.hasUsage)
    }

    @Test
    fun `should show nothing for another app used neither today nor yesterday`() = runBlocking {
        desk(500, daysAgo = 3)
        val history = historyWithDesk()

        history.read()

        assertNull(history.otherApps.first().report)
        assertTrue(history.usedOtherApps.isEmpty())
        assertFalse(history.hasUsage)
    }

    @Test
    fun `should keep each other app's days apart from the login's`() = runBlocking {
        val store = InMemoryLedgerStore()
        desk(500, daysAgo = 2)
        val history = historyWithDesk { DayLedger(store, it) }

        history.read()

        assertEquals(listOf("acme", "acme/Desk"), store.pages.keys.sorted())
    }

    // Kept days

    /**
     * A usage history's fingerprint names how its days were summed: when it changes, every kept
     * day is summed again, a month of logs read anew. These are the built-in definitions'
     * fingerprints as released. Price files are left out: a new price list re-sums the days, and is meant to.
     */
    @Test
    fun `should keep the days every built-in usage history has already summed`() {
        fun fingerprint(definition: UsageLog.Definition?) = UsageLog.make(definition!!, "/Users/someone", { null }, now = { 0.0 }).fingerprint
        val claude = TestDefinitions.builtIn("claude")
        val codex = TestDefinitions.builtIn("codex")

        assertEquals("b3bcc70b596fd9b04e17e3db8ad24d09352051cfd8fbac03070d464826171024", fingerprint(claude.usageHistory))
        assertEquals(
            "931d7ea6e4403964a2af69dd0de2d289ea13c65df6955d337b33e52173cc3f25",
            fingerprint(claude.usageHistoryForAccount(mapOf("configDirectory" to "/Users/someone/work-claude"))),
        )
        assertEquals("d43e7240f0b32898243293138562cd3503f2a69619691664482038c86e360427", fingerprint(claude.usageHistory?.otherApps?.first()?.definition))
        assertEquals("2db943b5a7ea6de29b14f66f92d48f028df8f2a176923d0ac3c9be7d1cb8b8ac", fingerprint(codex.usageHistory))
        assertEquals(
            "f64c646a4632e6262d600ca716d13a0addcf792e9e569bfaec672b9cf7cc05b7",
            fingerprint(codex.usageHistoryForAccount(mapOf("codexHome" to "/Users/someone/work-codex"))),
        )
        assertEquals("3e1157e243aa7b8bf21ff21cdab66d73f885f72bf7bd7f0c57dee7b56543bf0d", fingerprint(TestDefinitions.builtIn("mistral").usageHistory))
    }
}

/** Kept days in memory, by key. */
internal class InMemoryLedgerStore : LedgerStore {
    val pages = mutableMapOf<String, LedgerPage>()
    override fun load(key: String): LedgerPage? = pages[key]
    override fun save(page: LedgerPage, key: String) {
        pages[key] = page
    }
}
