package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.DailyUsageStat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.io.File

/** Kept days on disk: one small JSON file per login, read back exactly, in the format Swift writes. */
class FileLedgerStoreTest {
    private val directory = TestDefinitions.folder("ledger")
    private val store = FileLedgerStore(directory.path)

    @AfterEach
    fun cleanUp() {
        directory.deleteRecursively()
    }

    private val day = DailyUsageStat(
        dateSeconds = 1_759_449_600.0, totalCostNanos = 10_500_000, totalTokens = 1500, workingTime = 600.0, sessionCount = 1,
        inputTokens = 1000, outputTokens = 500, cacheCreationTokens = 0, cacheReadTokens = 0, cachedSavingsNanos = 2_700_000_000,
    )

    @Test
    fun `should read back kept days exactly as they were saved, with money exact`() {
        val page = LedgerPage("f1", mapOf("2025-10-03" to day))

        store.save(page, "claude")

        assertEquals(page, store.load("claude"))
    }

    @Test
    fun `should have no kept days when nothing was saved or the file is damaged`() {
        assertNull(store.load("claude"))
        File(directory, "claude.json").writeText("{")
        assertNull(store.load("claude"))
    }

    @Test
    fun `should keep each login's days in its own file`() {
        store.save(LedgerPage("a", emptyMap()), "claude")
        store.save(LedgerPage("b", emptyMap()), "claude.work")

        assertEquals("a", store.load("claude")?.fingerprint)
        assertEquals("b", store.load("claude.work")?.fingerprint)
    }

    @Test
    fun `should read the days a Swift build kept, dated from 2001 with money as numbers`() {
        File(directory, "claude.json").writeText(
            """{"fingerprint":"f1","days":{"2025-10-03":{"date":781142400,"totalCost":0.0105,"totalTokens":1500,"workingTime":600,""" +
                """"sessionCount":1,"inputTokens":1000,"outputTokens":500,"cacheCreationTokens":0,"cacheReadTokens":0,"cachedSavings":2.7}}}""",
        )

        assertEquals(LedgerPage("f1", mapOf("2025-10-03" to day)), store.load("claude"))
    }

    @Test
    fun `should write the days as a Swift build reads them`() {
        store.save(LedgerPage("f1", mapOf("2025-10-03" to day)), "claude/work")

        val saved = Json.parseToJsonElement(File(directory, "claude_work.json").readText()).jsonObject
        val stored = saved["days"]!!.jsonObject["2025-10-03"]!!.jsonObject
        assertEquals("781142400", stored["date"]!!.jsonPrimitive.content)
        assertEquals("0.0105", stored["totalCost"]!!.jsonPrimitive.content)
        assertEquals("2.7", stored["cachedSavings"]!!.jsonPrimitive.content)
        assertEquals("1500", stored["totalTokens"]!!.jsonPrimitive.content)
    }
}
