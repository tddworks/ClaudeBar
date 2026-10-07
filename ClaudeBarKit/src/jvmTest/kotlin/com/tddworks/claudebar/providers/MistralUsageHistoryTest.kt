package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.quotas.DailyUsageReport
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Mistral's usage history as data: `mistral.json`'s `usageHistory` reads Vibe's session folders —
 * one `meta.json` each, its time in the folder's UTC name — on the old analyzer's fixtures.
 */
class MistralUsageHistoryTest {
    private val home: File = Files.createTempDirectory("mistral-history").toRealPath().toFile()

    @AfterEach
    fun cleanUp() {
        home.deleteRecursively()
    }

    private fun report(): DailyUsageReport? = runBlocking {
        val definition = TestDefinitions.builtIn("mistral").usageHistory!!
        val history = UsageHistory(
            UsageLog.make(definition, home.path, { null }, TestDefinitions.builtIns::script, now = { System.currentTimeMillis() / 1000.0 }),
        )
        history.read()
        history.report
    }

    /** A session folder as Vibe names it: `session_YYYYMMDD_HHMMSS_<id>`, in UTC. */
    private fun session(at: Instant = Instant.now(), id: String = UUID.randomUUID().toString().take(6).lowercase(), meta: String?) {
        val name = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss").withZone(ZoneOffset.UTC).format(at)
        val dir = File(home, ".vibe/logs/session/session_${name}_$id").apply { mkdirs() }
        if (meta != null) File(dir, "meta.json").writeText(meta)
    }

    private fun meta(tokens: Int, cost: String = "0.00") = """{ "stats": { "session_total_llm_tokens": $tokens, "session_cost": $cost } }"""

    @Test
    fun `should sum today's Vibe sessions into today's tokens and session count`() {
        session(meta = meta(1500))
        session(meta = meta(3000))
        val today = report()!!.today
        assertEquals(4500L, today.totalTokens)
        assertEquals(2L, today.sessionCount)
        // A session's own time is not logged, so none is guessed.
        assertEquals(0.0, today.workingTime)
    }

    @Test
    fun `should count yesterday's sessions on yesterday`() {
        session(meta = meta(1500))
        session(at = Instant.now().atZone(ZoneId.systemDefault()).minusDays(1).toInstant(), meta = meta(3000))
        val report = report()!!
        assertEquals(1500L, report.today.totalTokens)
        assertEquals(3000L, report.previous.totalTokens)
    }

    @Test
    fun `should show each session's own cost exactly`() {
        session(meta = meta(50_000, "2.40"))
        assertEquals(2_400_000_000L, report()?.today?.totalCostNanos)
    }

    @Test
    fun `should skip a session whose log is broken or incomplete`() {
        session(meta = meta(1500))
        session(meta = "{ not valid json !! }")
        session(meta = """{ "title": "no stats" }""")
        session(meta = null)
        val today = report()!!.today
        assertEquals(1500L, today.totalTokens)
        assertEquals(1L, today.sessionCount)
    }

    @Test
    fun `should show no usage history when Vibe has no sessions`() {
        assertNull(report())
    }

    @Test
    fun `should date each session by its folder's name, in UTC`() {
        val rule = UsageLog.At.FromPath(pattern = """session_(\d{8}_\d{6})""", format = "yyyyMMdd_HHmmss", timeZone = "UTC")
        val definition = TestDefinitions.builtIn("mistral").usageHistory!!
        assertEquals(listOf(rule), definition.records.shapes.map { it.at })
        assertEquals(UsageLog.Format.JSON, definition.records.format)
    }
}
