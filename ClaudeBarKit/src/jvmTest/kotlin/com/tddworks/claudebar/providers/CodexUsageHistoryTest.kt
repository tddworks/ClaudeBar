package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.quotas.DailyUsageReport
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.ZoneOffset

/**
 * Codex's usage history as data: `codex.json`'s `usageHistory`, read from the session logs Codex
 * writes, one `token_count` line per turn.
 */
class CodexUsageHistoryTest {
    private val home: File = Files.createTempDirectory("codex-history").toRealPath().toFile()

    @AfterEach
    fun cleanUp() {
        home.deleteRecursively()
    }

    private fun log(definition: UsageLog.Definition) = UsageLog.make(
        definition, home.path, { null }, TestDefinitions.builtIns::script, now = { System.currentTimeMillis() / 1000.0 },
    )

    private fun history(): UsageHistory = UsageHistory(log(TestDefinitions.builtIn("codex").usageHistory!!))

    private fun report(): DailyUsageReport = runBlocking {
        val history = history()
        history.read()
        assertNotNull(history.report)
        history.report!!
    }

    private fun write(jsonl: String, name: String = "rollout-2026-10-04T08-00-00-test.jsonl") {
        val dir = File(home, ".codex/sessions/2026/10/04").also { it.mkdirs() }
        File(dir, name).writeText(jsonl)
    }

    /** ISO 8601 with milliseconds, as Codex writes it. */
    private fun stamp(at: Instant = Instant.now()): String =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX").withZone(ZoneOffset.UTC).format(at)

    private val yesterdayNoon: Instant
        get() = LocalDate.now().minusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().plusSeconds(43_200)

    /** A turn: `last` is this turn's usage, `total` the session's running sum. */
    private fun turn(input: Int, cached: Int, output: Int, totalInput: Int, totalOutput: Int, at: Instant = Instant.now()): String {
        val last = """{"input_tokens":$input,"cached_input_tokens":$cached,"output_tokens":$output,"total_tokens":${input + output}}"""
        val total = """{"input_tokens":$totalInput,"cached_input_tokens":$cached,"output_tokens":$totalOutput,"total_tokens":${totalInput + totalOutput}}"""
        return """{"timestamp":"${stamp(at)}","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":$total,"last_token_usage":$last}}}"""
    }

    @Test
    fun `should count each turn's tokens today, with cached input as cache reads`() {
        write(
            listOf(
                turn(input = 1000, cached = 600, output = 50, totalInput = 1000, totalOutput = 50),
                turn(input = 2000, cached = 1500, output = 80, totalInput = 3000, totalOutput = 130),
            ).joinToString("\n"),
        )

        val today = report().today

        assertEquals(900L, today.inputTokens) // (1000 − 600) + (2000 − 1500)
        assertEquals(2100L, today.cacheReadTokens)
        assertEquals(130L, today.outputTokens)
        assertEquals(1030L, today.totalTokens)
    }

    @Test
    fun `should count a turn once when Codex writes it twice`() {
        val turn = turn(input = 1000, cached = 0, output = 50, totalInput = 1000, totalOutput = 50)
        write(listOf(turn, turn).joinToString("\n"))

        assertEquals(1050L, report().today.totalTokens)
    }

    @Test
    fun `should count only the turns that carry usage`() {
        write(
            listOf(
                """{"timestamp":"${stamp()}","type":"event_msg","payload":{"type":"token_count","info":null}}""",
                """{"timestamp":"${stamp()}","type":"turn_context","payload":{"model":"gpt-x"}}""",
                turn(input = 100, cached = 0, output = 10, totalInput = 100, totalOutput = 10),
            ).joinToString("\n"),
        )

        assertEquals(110L, report().today.totalTokens)
    }

    @Test
    fun `should count yesterday's turns as yesterday's`() {
        write(
            listOf(
                turn(input = 100, cached = 0, output = 10, totalInput = 100, totalOutput = 10, at = yesterdayNoon),
                turn(input = 200, cached = 0, output = 20, totalInput = 300, totalOutput = 30),
            ).joinToString("\n"),
        )

        val report = report()

        assertEquals(110L, report.previous.totalTokens)
        assertEquals(220L, report.today.totalTokens)
    }

    @Test
    fun `should show no cost for Codex's history, since its logs name no model`() {
        assertFalse(history().knowsCost)
        val claude = TestDefinitions.builtIn("claude").usageHistory!!
        assertTrue(UsageHistory(log(claude)).knowsCost)
    }

    @Test
    fun `should read an added login's history from its own Codex folder`() {
        val definition = TestDefinitions.builtIn("codex")
        val account = definition.usageHistoryForAccount(mapOf("codexHome" to "/tmp/work-codex"))
        assertNotNull(account)
        assertEquals("/tmp/work-codex/sessions/**/rollout-*.jsonl", account!!.records.files)
    }
}
