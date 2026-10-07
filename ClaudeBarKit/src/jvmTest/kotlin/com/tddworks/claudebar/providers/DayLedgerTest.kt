package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.localCalendar
import com.tddworks.claudebar.quotas.DailyUsageStat
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId

/**
 * The ledger: a day that has closed is summed once and kept, never read from the logs again;
 * the open days — today, and yesterday until an hour past midnight — are read every time. A
 * change to how the logs read starts it over (daily-usage design §3). Reading the logs around
 * it is `UsageHistory`'s, and the lifecycle's to test.
 */
class DayLedgerTest {
    private class Shelf : LedgerStore {
        val pages = mutableMapOf<String, LedgerPage>()
        override fun load(key: String): LedgerPage? = pages[key]
        override fun save(page: LedgerPage, key: String) {
            pages[key] = page
        }
    }

    private val calendar = localCalendar()
    private val shelf = Shelf()
    private val ledger = DayLedger(shelf, "acme")

    private val today = calendar.startOfDay(System.currentTimeMillis() / 1000.0)

    /** Today at [hour] o'clock. */
    private fun todayAt(hour: Double) = today + hour * 3600

    private fun daysAgo(days: Int) = calendar.addingDays(-days, today)

    private fun day(start: Double, cost: Long) = DailyUsageStat(start, cost * 1_000_000_000, 1000, 0.0, 1, 0, 0, 0, 0, 0)

    private fun closedDays(count: Int, from: Int = 1) =
        (from until from + count).associate { DayLedger.name(daysAgo(it)) to day(daysAgo(it), it.toLong()) }

    @Test
    fun `should keep a closed day's usage after the logs are gone`() {
        ledger.keep(mapOf(DayLedger.name(daysAgo(1)) to day(daysAgo(1), 41)), "f1")

        val kept = DayLedger(shelf, "acme").days("f1")

        assertEquals(41_000_000_000, kept[DayLedger.name(daysAgo(1))]?.totalCostNanos)
    }

    @Test
    fun `should show today's latest usage every time it is read`() {
        assertFalse(DayLedger.isClosed(today, todayAt(12.0), calendar))
        assertFalse(DayLedger.isClosed(today, todayAt(23.99), calendar))
    }

    @Test
    fun `should keep reading yesterday from the logs until an hour past midnight`() {
        assertFalse(DayLedger.isClosed(daysAgo(1), todayAt(0.5), calendar))
        assertTrue(DayLedger.isClosed(daysAgo(1), todayAt(1.0), calendar))
    }

    @Test
    fun `should keep thirty closed days from one read and read only today again`() {
        ledger.keep(closedDays(10), "f1")
        ledger.keep(closedDays(19, from = 11), "f1")

        val kept = ledger.days("f1")

        assertEquals(29, kept.size)
        assertEquals(29_000_000_000, kept[DayLedger.name(daysAgo(29))]?.totalCostNanos)
        assertNull(kept[DayLedger.name(today)])
    }

    @Test
    fun `should keep a closed day with no usage as an empty day`() {
        ledger.keep(mapOf(DayLedger.name(daysAgo(1)) to DailyUsageStat.empty(daysAgo(1)), DayLedger.name(daysAgo(2)) to DailyUsageStat.empty(daysAgo(2))), "f1")

        assertEquals(2, shelf.pages["acme"]?.days?.size)
        assertTrue(shelf.pages["acme"]!!.days.values.all { it.isEmpty })
    }

    @Test
    fun `should read the logs again from scratch when how they are read changes`() {
        ledger.keep(closedDays(3), "f1")

        assertTrue(ledger.days("f2").isEmpty())
        ledger.keep(closedDays(1), "f2")
        assertEquals(1, ledger.days("f2").size)
        assertTrue(ledger.days("f1").isEmpty())
    }

    @Test
    fun `should keep nothing when there are no closed days to keep`() {
        ledger.keep(emptyMap(), "f1")

        assertTrue(shelf.pages.isEmpty())
    }

    @Test
    fun `should name each day by its local date`() {
        val expected = Instant.ofEpochSecond(today.toLong()).atZone(ZoneId.systemDefault()).toLocalDate().toString()

        assertEquals(expected, DayLedger.name(today))
        assertTrue(Regex("""\d{4}-\d{2}-\d{2}""").matches(DayLedger.name(daysAgo(1))))
    }
}
