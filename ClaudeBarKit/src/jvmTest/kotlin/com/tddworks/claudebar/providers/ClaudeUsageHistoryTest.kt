package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.datasources.logs.localCalendar
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.quotas.DailyUsageReport
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNotSame
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate

/**
 * Claude's usage history as data: `claude.json`'s `usageHistory` and `claude-prices.json`, run
 * on the old analyzer's fixtures — the same numbers *TODAY'S USAGE* showed before (#190, #207).
 */
class ClaudeUsageHistoryTest {
    private val stub = StubbedProvider()
    private val home = stub.home

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private val definition = TestDefinitions.builtIn("claude")

    private fun log(definition: UsageLog.Definition) =
        UsageLog.make(definition, home, { null }, TestDefinitions.builtIns::script, now = { System.currentTimeMillis() / 1000.0 })

    private fun history() = UsageHistory(log(definition.usageHistory!!))

    private fun report(): DailyUsageReport = runBlocking {
        val history = history()
        history.read()
        history.report ?: error("no report")
    }

    private fun write(jsonl: String, name: String = "test-session.jsonl") {
        val dir = File(home, ".claude/projects/test-project").apply { mkdirs() }
        File(dir, name).writeText(jsonl)
    }

    /** Claude Code's own config, where its route is. */
    private fun route(json: String) {
        File(home, ".claude.json").writeText(json)
    }

    private fun nanos(dollars: String): Long = BigDecimal(dollars).movePointRight(9).longValueExact()

    private fun nowSeconds() = System.currentTimeMillis() / 1000.0

    private fun stamp(atSeconds: Double = nowSeconds()): String = Instant.ofEpochMilli((atSeconds * 1000).toLong()).toString()

    private val yesterdayNoon: Double
        get() {
            val calendar = localCalendar()
            return calendar.addingDays(-1, calendar.startOfDay(nowSeconds())) + 43_200
        }

    private fun line(
        model: String = "claude-sonnet-4-6", input: Int = 1000, output: Int = 500, cacheWrite: Int = 0,
        cacheRead: Int = 0, message: String? = null, request: String? = null, at: Double = nowSeconds(),
    ): String {
        val requestId = request?.let { """"requestId":"$it",""" } ?: ""
        val messageId = message?.let { """"id":"$it",""" } ?: ""
        return """{"type":"assistant",$requestId"message":{$messageId"model":"$model","usage":{"input_tokens":$input,"output_tokens":$output,"cache_creation_input_tokens":$cacheWrite,"cache_read_input_tokens":$cacheRead}},"timestamp":"${stamp(at)}"}"""
    }

    @Test
    fun `should show today's tokens and cost from Claude Code's session logs`() {
        write(line())
        val report = report()
        assertEquals(1500L, report.today.totalTokens)
        assertEquals(nanos("0.0105"), report.today.totalCostNanos)
        assertTrue(report.previous.isEmpty)
    }

    @Test
    fun `should show no usage history when there are no session logs`() = runBlocking {
        val history = history()
        history.read()
        assertNull(history.report)
    }

    @Test
    fun `should count yesterday's usage apart from today's`() {
        write(listOf(line(), line(input = 2000, output = 1000, at = yesterdayNoon)).joinToString("\n"))
        val report = report()
        assertEquals(1500L, report.today.totalTokens)
        assertEquals(3000L, report.previous.totalTokens)
    }

    @Test
    fun `should show cache tokens, cache savings and the hit rate`() {
        write(line(cacheWrite = 2000, cacheRead = 1_000_000))
        val today = report().today
        assertEquals(listOf(1000L, 500L, 2000L, 1_000_000L), listOf(today.inputTokens, today.outputTokens, today.cacheCreationTokens, today.cacheReadTokens))
        assertEquals(nanos("2.7"), today.cachedSavingsNanos)
        assertTrue(today.cacheHitRate > 0.99)
    }

    // Streamed and copied messages count once (#207)

    @Test
    fun `should count a message once when it is repeated across content blocks (#207)`() {
        val line = line(message = "msg_A", request = "req_1")
        write(listOf(line, line, line).joinToString("\n"))
        assertEquals(1500L, report().today.totalTokens)
    }

    @Test
    fun `should count a streamed message at its final size (#207)`() {
        val now = nowSeconds()
        write(listOf(
            line(output = 1, message = "msg_A", request = "req_1", at = now),
            line(output = 1, message = "msg_A", request = "req_1", at = now + 0.1),
            line(output = 500, message = "msg_A", request = "req_1", at = now + 0.9),
        ).joinToString("\n"))
        val today = report().today
        assertEquals(500L, today.outputTokens)
        assertEquals(1500L, today.totalTokens)
    }

    @Test
    fun `should count a response once when a resumed session copies it into another file (#207)`() {
        val line = line(message = "msg_A", request = "req_1")
        write(line, "session-1.jsonl")
        write(line, "session-2.jsonl")
        assertEquals(1500L, report().today.totalTokens)
    }

    @Test
    fun `should count every line that has no message or request id`() {
        val line = line()
        write(listOf(line, line).joinToString("\n"))
        assertEquals(3000L, report().today.totalTokens)
    }

    // Prices from claude-prices.json

    @Test
    fun `should price models as Anthropic lists them, estimating unknown ones`() {
        // 1M in / 100K out / 1M cache write / 1M cache read each.
        write(listOf(
            line("claude-sonnet-4-6", input = 1_000_000, output = 100_000, cacheWrite = 1_000_000, cacheRead = 1_000_000, message = "a", request = "1"),
            line("claude-opus-4-99-20260101", input = 1_000_000, output = 0, message = "b", request = "2"),
            line("glm-4.6", input = 1_000_000, output = 0, message = "c", request = "3"),
        ).joinToString("\n"))
        // Sonnet $8.55, an unknown Opus at Opus 4.6's $5 input, a paid gateway's model at the Sonnet estimate $3.
        assertEquals(nanos("16.55"), report().today.totalCostNanos)
    }

    @Test
    fun `should price the current models at today's list prices`() {
        write(listOf(
            line("claude-opus-5-5", input = 1_000_000, output = 100_000, message = "a", request = "1"),
            line("claude-haiku-4-5-20251001", input = 1_000_000, output = 0, cacheRead = 1_000_000, message = "b", request = "2"),
        ).joinToString("\n"))
        // Opus 5.5: $4 + $2; Haiku 4.5, dated: $1 + $0.10 of cache reads.
        assertEquals(nanos("7.1"), report().today.totalCostNanos)
    }

    @Test
    fun `should charge the one-hour price for cache writes kept an hour`() {
        write("""{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":100000,"ephemeral_1h_input_tokens":900000}}},"timestamp":"${stamp()}"}""")
        val today = report().today
        // Opus 5.5: 0.1M × $5 + 0.9M × $8 of writes, $0.004 in, $0.01 out.
        assertEquals(nanos("7.714"), today.totalCostNanos)
        assertEquals(1_000_000L, today.cacheCreationTokens)
    }

    // Local inference costs nothing (#190)

    @Test
    fun `should cost nothing and save nothing when the model is open-weight (#190)`() {
        write(line("qwen3-coder:30b", cacheRead = 1_000_000))
        val today = report().today
        assertEquals(0L, today.totalCostNanos)
        assertEquals(0L, today.cachedSavingsNanos)
        assertEquals(1_000_000L, today.cacheReadTokens)
        assertEquals(1500L, today.totalTokens)
    }

    @Test
    fun `should cost nothing when an unpriced model runs while Claude Code is routed at this Mac (#190)`() {
        route("""{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}""")
        write(line("acme-internal-7b", cacheRead = 1_000_000))
        val today = report().today
        assertEquals(0L, today.totalCostNanos)
        assertEquals(0L, today.cachedSavingsNanos)
    }

    @Test
    fun `should treat Claude Code as local when only its providers list a local route (#190)`() {
        route("""{"providers":[{"base_url":"https://api.anthropic.com"},{"env":{"ANTHROPIC_BASE_URL":"http://[::1]:11434"}}]}""")
        write(line("some-unknown-model"))
        assertEquals(0L, report().today.totalCostNanos)
    }

    @Test
    fun `should keep the estimate when a remote route outranks a local provider entry`() {
        route("""{"env":{"ANTHROPIC_BASE_URL":"https://api.z.ai/api/anthropic"},"providers":[{"base_url":"http://localhost:11434"}]}""")
        write(line("some-unknown-model"))
        assertEquals(nanos("0.0105"), report().today.totalCostNanos)
    }

    @Test
    fun `should keep a known Anthropic model's list price on a local route`() {
        route("""{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:1234"}}""")
        write(line())
        assertEquals(nanos("0.0105"), report().today.totalCostNanos)
    }

    @Test
    fun `should keep yesterday's estimate when Claude Code is routed locally only now`() {
        route("""{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}""")
        write(line("some-unknown-model", at = yesterdayNoon))
        val report = report()
        assertTrue(report.today.isEmpty)
        assertEquals(nanos("0.0105"), report.previous.totalCostNanos)
        assertEquals(1500L, report.previous.totalTokens)
    }

    // Each login reads its own folder

    /** Claude with one added login in [work], every history over [home]. */
    private fun provider(work: File): Provider {
        val connections = stub.connections()
        val make = { history: UsageLog.Definition -> UsageHistory(log(history)) }
        return Provider(
            definition = definition,
            settings = InMemoryProviderSettings(),
            saved = listOf(ProviderAccountConfig(
                accountId = "work", label = "", email = "work@example.com",
                probeConfig = mapOf("configDirectory" to work.path, "loginEmail" to "work@example.com", "credentialService" to "fixture-work"),
            )),
            makeDataSource = { source, _ -> connections.make(source, "claude") },
            usageHistory = definition.usageHistory?.let(make),
            makeUsageHistory = { history, _ -> make(history) },
            folders = InMemoryLoginFolders(),
            paths = HomePaths(home),
            isExecutable = { true },
            locate = { it },
        )
    }

    @Test
    fun `should show an added login the usage from its own config folder, never the default's`() = runBlocking {
        val work = File(home, "work-claude")
        File(work, "projects/p").mkdirs()
        File(work, "projects/p/s.jsonl").writeText(line(input = 2000, output = 1000))
        write(line())
        val provider = provider(work)
        val added = provider.accounts.first { !it.isDefault }

        provider.defaultAccount.usageHistory?.read()
        added.usageHistory?.read()

        assertEquals(1500L, provider.defaultAccount.usageHistory?.report?.today?.totalTokens)
        assertEquals(3000L, added.usageHistory?.report?.today?.totalTokens)
        assertNotSame(provider.defaultAccount.usageHistory, added.usageHistory)
    }

    @Test
    fun `should cost nothing when an added login's own folder routes Claude Code at this Mac`() = runBlocking {
        val work = File(home, "work-claude")
        File(work, "projects/p").mkdirs()
        File(work, "projects/p/s.jsonl").writeText(line("acme-internal-7b"))
        File(work, ".claude.json").writeText("""{"env":{"ANTHROPIC_BASE_URL":"http://localhost:11434"}}""")
        val added = provider(work).accounts.first { !it.isDefault }

        added.usageHistory?.read()

        assertEquals(0L, added.usageHistory?.report?.today?.totalCostNanos)
    }

    @Test
    fun `should drop an added login's usage history when the login is removed`() {
        val provider = provider(File(home, "work-claude"))
        val added = provider.accounts.first { !it.isDefault }
        assertNotNull(added.usageHistory)

        provider.accounts.remove(added)

        assertNull(added.usageHistory)
    }

    @Test
    fun `should read an added login's logs and route from its config folder, and have no history without one`() {
        val own = definition.usageHistoryForAccount(mapOf("configDirectory" to "/tmp/work"))
        assertNotNull(own)
        assertEquals("/tmp/work/projects/**/*.jsonl", own!!.records.files)
        assertEquals("/tmp/work/.claude.json", own.freeWhen?.localEndpoint?.file)
        assertEquals(2, own.freeWhen?.localEndpoint?.url?.size)
        assertNull(definition.usageHistoryForAccount(emptyMap()))
    }

    @Test
    fun `should leave the Mac's other apps out of an added login's history`() {
        assertEquals(listOf("Claude Desktop"), definition.usageHistory?.otherApps?.map { it.label })
        assertNull(definition.usageHistoryForAccount(mapOf("configDirectory" to "/tmp/work"))?.otherApps)
    }

    // Claude Desktop's buddy-tokens.json (#198)

    private fun desktop(): UsageHistory = runBlocking {
        val history = UsageHistory(definition.usageHistory!!, login = "claude", log = ::log)
        history.read()
        history.otherApps.first()
    }

    private fun buddyTokens(body: String) {
        val dir = File(home, "Library/Application Support/Claude").apply { mkdirs() }
        File(dir, "buddy-tokens.json").writeText(body)
    }

    private fun day(daysAgo: Long = 0): String = LocalDate.now().minusDays(daysAgo).toString()

    @Test
    fun `should show Claude Desktop's tokens today as their own history, with no cost (#198)`() {
        write(line())
        buddyTokens("""{"tokens-today": {"date": "${day()}", "tokens": 74422}}""")

        val desktop = desktop()

        assertEquals("Claude Desktop", desktop.label)
        assertEquals(74_422L, desktop.report?.today?.totalTokens)
        assertFalse(desktop.knowsCost)
    }

    @Test
    fun `should count Claude Desktop's tokens as yesterday's, with nothing today yet, when it wrote them yesterday`() {
        buddyTokens("""{"tokens-today": {"date": "${day(1)}", "tokens": 61210}}""")

        val report = desktop().report!!

        assertEquals(61_210L, report.previous.totalTokens)
        assertTrue(report.today.isEmpty)
    }

    @ParameterizedTest
    @ValueSource(strings = [
        "{ nope",
        """{"something-else": {}}""",
        """{"tokens-today": {"tokens": 100}}""",
        """{"tokens-today": {"date": "May 28 2026", "tokens": 100}}""",
        """{"tokens-today": {"date": "2026-02-30", "tokens": 100}}""",
        """{"tokens-today": {"date": "2099-12-31", "tokens": 100}}""",
    ])
    fun `should show nothing for Claude Desktop when its tokens file changes shape`(body: String) {
        buddyTokens(body)
        assertNull(desktop().report)
    }

    @ParameterizedTest
    @ValueSource(strings = ["-5", "74422.5"])
    fun `should show nothing for Claude Desktop when its token count is negative or fractional`(count: String) {
        buddyTokens("""{"tokens-today": {"date": "${day()}", "tokens": $count}}""")
        assertNull(desktop().report)
    }

    @Test
    fun `should show nothing for Claude Desktop when it isn't on this Mac`() {
        assertNull(desktop().report)
    }
}
