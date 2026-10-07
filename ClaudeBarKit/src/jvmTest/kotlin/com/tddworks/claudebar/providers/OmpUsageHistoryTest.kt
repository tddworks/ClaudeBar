package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.quotas.DailyUsageReport
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Oh My Pi's usage history as data: `omp.json`'s `usageHistory`, read from the session
 * transcripts omp writes under `~/.omp/agent/sessions` — an assistant turn per model reply, and a
 * `model_usage` entry per model call made outside the conversation.
 */
class OmpUsageHistoryTest {
    private val home: File = Files.createTempDirectory("omp-history").toRealPath().toFile()

    private val sessions: File get() = File(home, ".omp/agent/sessions")

    @AfterEach
    fun cleanUp() {
        home.deleteRecursively()
    }

    private fun history(environment: (String) -> String? = { null }): UsageHistory {
        val definition: UsageLog.Definition = TestDefinitions.builtIn("omp").usageHistory!!
        return UsageHistory(
            UsageLog.make(definition, home.path, environment, TestDefinitions.builtIns::script, now = { System.currentTimeMillis() / 1000.0 }),
        )
    }

    private fun report(environment: (String) -> String? = { null }): DailyUsageReport = runBlocking {
        val history = history(environment)
        history.read()
        assertNotNull(history.report)
        history.report!!
    }

    /**
     * A transcript at [path] under the sessions folder: `<project>/<session>.jsonl` for a main
     * session, one folder deeper for a subagent's or the advisor's.
     */
    private fun write(lines: List<String>, path: String = "-work-app/2026-10-06T08-00-00-000Z_main.jsonl", folder: File? = null) {
        val file = File(folder ?: sessions, path)
        file.parentFile.mkdirs()
        file.writeText(lines.joinToString("\n"))
    }

    private fun stamp(at: Instant): String =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSXXX").withZone(ZoneOffset.UTC).format(at)

    private val yesterdayNoon: Instant
        get() = LocalDate.now().minusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().plusSeconds(43_200)

    private fun entryId(): String = UUID.randomUUID().toString().take(8).lowercase()

    private fun usage(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, cost: String): String {
        val total = input + output + cacheRead + cacheWrite
        return """{"input":$input,"output":$output,"cacheRead":$cacheRead,"cacheWrite":$cacheWrite,"totalTokens":$total,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":$cost}}"""
    }

    /** An assistant turn, as omp writes it. */
    private fun turn(
        id: String = entryId(), at: Instant = Instant.now(), input: Int, output: Int,
        cacheRead: Int = 0, cacheWrite: Int = 0, cost: String = "0",
    ): String {
        val usage = usage(input, output, cacheRead, cacheWrite, cost)
        val millis = at.toEpochMilli()
        return """{"type":"message","id":"$id","parentId":null,"timestamp":"${stamp(at)}","message":{"role":"assistant","content":[{"type":"text","text":"ok"}],"api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":$usage,"stopReason":"stop","timestamp":$millis}}"""
    }

    /** A model call omp makes outside the conversation — here its memory's. */
    private fun sideCall(at: Instant = Instant.now(), input: Int, output: Int, cacheWrite: Int = 0, cost: String = "0"): String {
        val usage = usage(input, output, 0, cacheWrite, cost)
        return """{"type":"model_usage","id":"${entryId()}","parentId":null,"timestamp":"${stamp(at)}","purpose":"memory","role":"memory","api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":$usage,"stopReason":"stop"}"""
    }

    private fun ask(text: String): String =
        """{"type":"message","id":"${entryId()}","parentId":null,"timestamp":"${stamp(Instant.now())}","message":{"role":"user","content":"$text"}}"""

    /** The `task` tool's result: `details.usage` is the sum of its subagent's turns. */
    private fun taskResult(input: Int, output: Int): String {
        val usage = usage(input, output, 0, 0, "0")
        return """{"type":"message","id":"${entryId()}","parentId":null,"timestamp":"${stamp(Instant.now())}","message":{"role":"toolResult","toolCallId":"call_1","toolName":"task","content":[{"type":"text","text":"done"}],"details":{"usage":$usage}}}"""
    }

    // Turns

    @Test
    fun `should count each turn's tokens today, cache reads and writes apart from input`() {
        write(
            listOf(
                ask("refactor the parser"),
                turn(input = 2, output = 357, cacheRead = 66_582, cacheWrite = 10_228),
                turn(input = 10, output = 20, cacheRead = 100),
            ),
        )

        val today = report().today

        assertEquals(12L, today.inputTokens)
        assertEquals(377L, today.outputTokens)
        assertEquals(66_682L, today.cacheReadTokens)
        assertEquals(10_228L, today.cacheCreationTokens)
        assertEquals(389L, today.totalTokens)
    }

    @Test
    fun `should count yesterday's turns as yesterday's`() {
        write(
            listOf(
                turn(at = yesterdayNoon, input = 100, output = 10),
                turn(input = 200, output = 20),
            ),
        )

        val report = report()

        assertEquals(110L, report.previous.totalTokens)
        assertEquals(220L, report.today.totalTokens)
    }

    @Test
    fun `should show the cost omp recorded for each call`() {
        write(
            listOf(
                turn(input = 100, output = 10, cost = "0.25"),
                sideCall(input = 5, output = 1, cost = "0.125"),
            ),
        )

        assertTrue(history().knowsCost)
        assertEquals(375_000_000L, report().today.totalCostNanos)
    }

    // Which entries count

    @Test
    fun `should count the model calls omp makes outside the conversation`() {
        write(
            listOf(
                turn(input = 100, output = 10),
                sideCall(input = 507, output = 321, cacheWrite = 616),
            ),
        )

        val today = report().today

        assertEquals(607L, today.inputTokens)
        assertEquals(331L, today.outputTokens)
        assertEquals(616L, today.cacheCreationTokens)
    }

    @Test
    fun `should count subagent and advisor transcripts beside the main session`() {
        val session = "-work-app/2026-10-06T08-00-00-000Z_main"
        write(listOf(turn(input = 1, output = 1)), "$session.jsonl")
        write(listOf(turn(input = 10, output = 10)), "$session/Explorer.jsonl")
        write(listOf(turn(input = 100, output = 100)), "$session/__advisor.jsonl")
        write(listOf(turn(input = 1000, output = 1000)), "$session/Explorer/Reviewer.jsonl")

        assertEquals(2222L, report().today.totalTokens)
    }

    @Test
    fun `should not count a task's summed usage, which its subagent's transcript already counts`() {
        val session = "-work-app/2026-10-06T08-00-00-000Z_main"
        write(listOf(turn(input = 1, output = 1), taskResult(input = 40, output = 2)), "$session.jsonl")
        write(listOf(turn(input = 40, output = 2)), "$session/Explorer.jsonl")

        assertEquals(44L, report().today.totalTokens)
    }

    // Copies

    @Test
    fun `should count a turn once when a forked session copies it`() {
        val turn = turn(input = 1000, output = 50)
        write(listOf(turn), "-work-app/2026-10-06T08-00-00-000Z_parent.jsonl")
        write(listOf(turn, turn(input = 10, output = 5)), "-work-app/2026-10-06T09-00-00-000Z_fork.jsonl")

        assertEquals(1065L, report().today.totalTokens)
    }

    @Test
    fun `should count two turns that share an entry id at different times`() {
        write(listOf(turn(id = "1a2b3c4d", input = 1000, output = 50)), "-work-app/a.jsonl")
        write(listOf(turn(id = "1a2b3c4d", at = Instant.now().minusSeconds(1), input = 10, output = 5)), "-work-other/b.jsonl")

        assertEquals(1065L, report().today.totalTokens)
    }

    // Where

    @Test
    fun `should read the sessions of the agent folder PI_CODING_AGENT_DIR names`() {
        val agent = File(home, "custom-agent")
        write(listOf(turn(input = 30, output = 3)), folder = File(agent, "sessions"))

        val path = agent.path
        val today = report(environment = { if (it == "PI_CODING_AGENT_DIR") path else null }).today

        assertEquals(33L, today.totalTokens)
    }

    @Test
    fun `should give Oh My Pi's login a usage history its tokens can be shared from`() {
        val stub = StubbedProvider()
        try {
            val engine = Engine(
                settings = InMemoryProviderSettings(),
                connections = stub.connections(),
                home = stub.home,
                environment = { null },
                folders = stub.folders,
                paths = HomePaths(stub.home),
                isExecutable = { true },
                locate = { it },
                vault = MemoryVault(),
                now = { System.currentTimeMillis() / 1000.0 },
            )
            val provider = ProviderFactory(engine, TestDefinitions.builtIns).make("omp")

            assertNotNull(provider.defaultAccount.usageHistory)
        } finally {
            stub.cleanUp()
        }
    }
}
