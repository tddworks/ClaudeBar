package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.ProcessEnvironment
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.UUID

/**
 * One session shared by every run of a CLI call (#132). The definition carries only the
 * vendor's facts; which session a worker is in is its own memory: create once, resume after,
 * recreate when gone, the plain invocation when the flags are refused.
 */
class CLISessionTest {
    private val usageScreen = "Current session\n████████████████░░░░ 65% left\nResets in 2h 15m"

    private fun session() = CLICall.Session(
        create = listOf("--session-id", "{{id}}", "--name", "ClaudeBar Probe"),
        resume = listOf("--resume", "{{id}}"),
        recreateOn = listOf("no conversation found", "no session found"),
        unsupportedOn = listOf("unknown option '--session-id'", "unknown option '--resume'", "unknown option '--name'"),
    )

    private fun call(args: List<String> = listOf("/usage", "--allowed-tools", ""), session: CLICall.Session) =
        CLICall(cli = "claude", args = args, timeout = 20.0, session = session)

    /** Hands out [ids] in order. */
    private fun idQueue(vararg ids: String): () -> String {
        val queue = ArrayDeque(ids.toList())
        var index = 0
        return { synchronized(queue) { queue.removeFirstOrNull() ?: "unexpected-id-${index++}" } }
    }

    private fun runner(call: CLICall, executor: FakeCLIExecutor, ids: () -> String = idQueue(), memory: SessionMemory = SessionMemory()) =
        CLISessionRunner(call, call.session ?: session(), null, { executor }, memory, ids)

    private fun screen(text: String, exitCode: Int = 0) = FakeCLIExecutor("/usr/local/bin/claude") { CLIResult(text, exitCode) }

    private val FakeCLIExecutor.launches: List<List<String>> get() = executions.map { it.args }

    private fun decode(json: String): CLICall = DefinitionJson.decodeFromString(CLICall.serializer(), json)
    private fun encode(call: CLICall): String = DefinitionJson.encodeToString(CLICall.serializer(), call)

    // The definition side

    @Test
    fun `should read a session's create and resume arguments and its gone and refused phrases from the definition`() {
        val call = decode(
            """
            {"cli":"claude","args":["/usage"],
             "session":{"create":["--session-id","{{id}}","--name","ClaudeBar Probe"],
                        "resume":["--resume","{{id}}"],
                        "recreateOn":["no conversation found"],
                        "unsupportedOn":["unknown option '--session-id'"]}}
            """,
        )

        val session = call.session!!
        assertEquals(listOf("--session-id", "{{id}}", "--name", "ClaudeBar Probe"), session.create)
        assertEquals(listOf("--resume", "{{id}}"), session.resume)
        assertEquals(listOf("no conversation found"), session.recreateOn)
        assertEquals(listOf("unknown option '--session-id'"), session.unsupportedOn)
    }

    @Test
    fun `should treat no session as gone or refused when the definition names no phrases`() {
        val call = decode("""{"cli":"claude","session":{"create":["--session-id","{{id}}"],"resume":["--resume","{{id}}"]}}""")

        assertTrue(call.session!!.recreateOn.isEmpty())
        assertTrue(call.session!!.unsupportedOn.isEmpty())
    }

    @Test
    fun `should write no session when the CLI call has none`() {
        val call = CLICall(cli = "claude", args = listOf("/usage"))
        val json = encode(call)

        assertFalse("session" in json)
        assertEquals(call, decode(json))
    }

    @Test
    fun `should keep the session when the definition is written out and read back`() {
        val call = call(session = session())

        assertEquals(call, decode(encode(call)))
    }

    // The plan loop

    @Test
    fun `should create and name a session on the first run and remember its id`() = runBlocking {
        val executor = screen(usageScreen)
        val memory = SessionMemory()

        val result = runner(call(session = session()), executor, idQueue("11111111-2222-3333-4444-555555555555"), memory).run()

        assertEquals(usageScreen, result.output)
        assertEquals(
            listOf(listOf("/usage", "--allowed-tools", "", "--session-id", "11111111-2222-3333-4444-555555555555", "--name", "ClaudeBar Probe")),
            executor.launches,
        )
        assertEquals("11111111-2222-3333-4444-555555555555", memory.id)
    }

    @Test
    fun `should resume the session it created on every later run`() = runBlocking {
        val executor = screen(usageScreen)
        val memory = SessionMemory()
        val runner = runner(call(session = session()), executor, idQueue("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), memory)

        repeat(3) { runner.run() }

        val launches = executor.launches
        assertEquals(3, launches.size)
        assertTrue("--session-id" in launches[0])
        assertEquals(listOf("/usage", "--allowed-tools", "", "--resume", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), launches[1])
        assertEquals(listOf("/usage", "--allowed-tools", "", "--resume", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), launches[2])
        assertEquals("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", memory.id)
    }

    @Test
    fun `should create a fresh session when the CLI says the remembered one is gone`() = runBlocking {
        val gone = "No conversation found with session ID aaaaaaaaaa"
        val executor = FakeCLIExecutor { CLIResult(if ("--resume" in it.args) gone else usageScreen) }
        val memory = SessionMemory().apply { remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") }

        val result = runner(call(session = session()), executor, idQueue("11111111-2222-3333-4444-555555555555"), memory).run()

        assertEquals(usageScreen, result.output)
        assertEquals(2, executor.launches.size)
        assertTrue("--resume" in executor.launches[0])
        assertEquals(
            listOf("/usage", "--allowed-tools", "", "--session-id", "11111111-2222-3333-4444-555555555555", "--name", "ClaudeBar Probe"),
            executor.launches[1],
        )
        assertEquals("11111111-2222-3333-4444-555555555555", memory.id)
    }

    @Test
    fun `should create a fresh session when the CLI says the remembered one is gone, word by word as a TUI paints it`() = runBlocking {
        // The CLI positions each word with a cursor move: the bytes never hold the phrase as one run.
        val gone = "\u001B7\u001B[r\u001B8\u001B[?25h\u001B[?2031l\u001B[?2004lNo\u001B[4Gconversation\u001B[17Gfound\u001B[23Gwith" +
            "\u001B[28Gsession\u001B[36GID:\u001B[40Gaaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\r\r\n"
        val executor = FakeCLIExecutor {
            if ("--resume" in it.args) CLIResult(gone, 1) else CLIResult(usageScreen, 0)
        }
        val memory = SessionMemory().apply { remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") }

        val result = runner(call(session = session()), executor, idQueue("11111111-2222-3333-4444-555555555555"), memory).run()

        assertEquals(usageScreen, result.output)
        assertEquals(2, executor.launches.size)
        assertEquals("11111111-2222-3333-4444-555555555555", memory.id)
    }

    @Test
    fun `should run the CLI plainly for good when this CLI build rejects the session flags`() = runBlocking {
        val refused = "error: unknown option '--session-id'"
        val executor = FakeCLIExecutor {
            CLIResult(if ("--session-id" in it.args || "--resume" in it.args) refused else usageScreen, 1)
        }
        val memory = SessionMemory()
        val runner = runner(call(session = session()), executor, idQueue("11111111-2222-3333-4444-555555555555"), memory)

        val first = runner.run()
        val second = runner.run()

        assertEquals(usageScreen, first.output)
        assertEquals(usageScreen, second.output)
        // Create refused → plain retry; the memory keeps every later run plain.
        val launches = executor.launches
        assertEquals(3, launches.size)
        assertTrue("--session-id" in launches[0])
        assertEquals(listOf("/usage", "--allowed-tools", ""), launches[1])
        assertEquals(listOf("/usage", "--allowed-tools", ""), launches[2])
        assertNull(memory.id)
        assertTrue(memory.isRefused)
    }

    @Test
    fun `should run plainly and forget the session when the CLI rejects resuming it`() = runBlocking {
        val refused = "error: unknown option '--resume'"
        val executor = FakeCLIExecutor { CLIResult(if ("--resume" in it.args) refused else usageScreen, 1) }
        val memory = SessionMemory().apply { remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") }

        runner(call(session = session()), executor, memory = memory).run()

        assertEquals(2, executor.launches.size)
        assertTrue("--resume" in executor.launches[0])
        assertEquals(listOf("/usage", "--allowed-tools", ""), executor.launches[1])
        assertNull(memory.id)
    }

    @Test
    fun `should keep the session when a successful screen merely mentions an unknown option`() = runBlocking {
        // A hook or transcript can carry the words; only a failed run proves the build rejects the flags.
        val chatty = "Tip: passing an unknown option '--session-id' used to error out.\n$usageScreen"
        val executor = screen(chatty)
        val memory = SessionMemory()

        runner(call(session = session()), executor, idQueue("11111111-2222-3333-4444-555555555555"), memory).run()

        assertEquals(1, executor.launches.size)
        assertTrue("--session-id" in executor.launches[0])
        assertEquals("11111111-2222-3333-4444-555555555555", memory.id)
    }

    // The detection rules

    @Test
    fun `should count the flags as rejected only when the CLI fails and says a refusal phrase`() {
        val tokens = session().unsupportedOn
        val refused = CLIResult("error: unknown option '--session-id'", 1)

        assertTrue(CLISessionRunner.isRefused(refused, tokens))
        assertFalse(CLISessionRunner.isRefused(CLIResult("error: unknown option '--session-id'", 0), tokens))
        assertFalse(CLISessionRunner.isRefused(CLIResult("boom", 1), tokens))
        assertFalse(CLISessionRunner.isRefused(refused, emptyList()))
    }

    @Test
    fun `should recognise a refusal phrase in any letter case`() {
        assertTrue(CLISessionRunner.isRefused(CLIResult("ERROR: UNKNOWN OPTION '--session-id'", 1), listOf("unknown option '--session-id'")))
    }

    @Test
    fun `should recognise a gone-session phrase in any letter case, and nothing else`() {
        assertTrue(CLISessionRunner.isGone("No Conversation Found With Session ID x", listOf("no conversation found")))
        assertFalse(CLISessionRunner.isGone("all good", listOf("no conversation found")))
        assertFalse(CLISessionRunner.isGone("all good", emptyList()))
    }

    // The memory

    @Test
    fun `should forget the session for good when many runs see the flags rejected at once`() = runBlocking {
        val memory = SessionMemory().apply { remember("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") }
        assertFalse(memory.isRefused)

        (0 until 50).map { async(kotlinx.coroutines.Dispatchers.Default) { memory.refuse() } }.awaitAll()

        assertTrue(memory.isRefused)
        assertNull(memory.id)
    }

    // The fetcher wiring

    private fun fetcher(call: CLICall, executor: FakeCLIExecutor) = CLIFetcher(call, { executor }, { "/dedicated" })

    @Test
    fun `should create a session once and then resume it when the definition asks for one`() = runBlocking {
        val executor = screen(usageScreen)
        val fetcher = fetcher(
            call(session = CLICall.Session(create = listOf("--session-id", "{{id}}", "--name", "ClaudeBar Probe"), resume = listOf("--resume", "{{id}}"))),
            executor,
        )

        fetcher.fetch(null)
        fetcher.fetch(null)

        assertEquals(2, executor.launches.size)
        assertTrue("--session-id" in executor.launches[0])
        assertTrue("--resume" in executor.launches[1])
    }

    @Test
    fun `should keep a separate session for each of two logins`() = runBlocking {
        val executor = screen(usageScreen)
        val plan = CLICall.Session(create = listOf("--session-id", "{{id}}"), resume = listOf("--resume", "{{id}}"))

        fetcher(call(session = plan), executor).fetch(null)
        fetcher(call(session = plan), executor).fetch(null)

        val created = executor.launches.mapNotNull { args -> args.indexOf("--session-id").takeIf { it >= 0 }?.let { args[it + 1] } }
        assertEquals(2, created.size)
        assertEquals(2, created.toSet().size)
    }

    @Test
    fun `should run the CLI with its plain arguments when the definition asks for no session`() = runBlocking {
        val executor = screen(usageScreen)

        val response = fetcher(CLICall(cli = "claude", args = listOf("/usage", "--allowed-tools", ""), timeout = 20.0), executor).fetch(null)

        assertEquals(listOf(listOf("/usage", "--allowed-tools", "")), executor.launches)
        assertTrue("65% left" in response.text)
    }

    // A stable session: one id per login, the same forever

    private fun stableSession() = CLICall.Session(
        id = CLICall.Session.Id(stable = "ClaudeBar Probe"),
        create = listOf("--session-id", "{{id}}", "--name", "ClaudeBar Probe"),
        resume = listOf("--resume", "{{id}}"),
        resumeOn = listOf("already in use"),
        unsupportedOn = listOf("unknown option '--session-id'"),
    )

    private fun stableCall(folder: String? = null) = CLICall(
        cli = "claude", args = listOf("/usage", "--allowed-tools", ""), timeout = 20.0,
        environment = ProcessEnvironment(set = folder?.let { mapOf("CLAUDE_CONFIG_DIR" to it) } ?: emptyMap()),
        session = stableSession(),
    )

    /** The id a run was given, from its `--session-id` or `--resume` argument. */
    private fun sessionId(args: List<String>): String? {
        for (flag in listOf("--session-id", "--resume")) {
            val at = args.indexOf(flag)
            if (at >= 0 && at + 1 < args.size) return args[at + 1]
        }
        return null
    }

    @Test
    fun `should create the session under the same id on every run, without a resume first`() = runBlocking {
        val executor = screen(usageScreen)
        val runner = runner(stableCall(), executor)

        runner.run()
        runner.run()

        assertEquals(2, executor.launches.size)
        assertTrue(executor.launches.all { "--resume" !in it && "--session-id" in it })
        val ids = executor.launches.mapNotNull(::sessionId)
        assertEquals(2, ids.size)
        assertEquals(ids[0], ids[1])
        assertEquals(ids[0], UUID.fromString(ids[0]).toString())
    }

    @Test
    fun `should keep a login's session id across restarts`() = runBlocking {
        val before = screen(usageScreen)
        val after = screen(usageScreen)

        runner(stableCall("/Users/me/.claude"), before).run()
        runner(stableCall("/Users/me/.claude"), after, memory = SessionMemory()).run()

        assertEquals(sessionId(before.launches.first()), sessionId(after.launches.first()))
    }

    @Test
    fun `should give a login in another folder its own session id`() = runBlocking {
        val personal = screen(usageScreen)
        val work = screen(usageScreen)

        runner(stableCall(), personal).run()
        runner(stableCall("/Users/me/work-claude"), work).run()

        assertNotEquals(sessionId(personal.launches.first()), sessionId(work.launches.first()))
    }

    @Test
    fun `should resume the same id when the CLI says the session is already in use`() = runBlocking {
        val taken = "Error: Session\u001B[8GID\u001B[11Gis\u001B[14Galready\u001B[22Gin\u001B[25Guse"
        val executor = FakeCLIExecutor {
            if ("--resume" in it.args) CLIResult(usageScreen, 0) else CLIResult(taken, 1)
        }

        val result = runner(stableCall(), executor).run()

        assertEquals(usageScreen, result.output)
        assertEquals(2, executor.launches.size)
        assertTrue("--resume" in executor.launches[1])
        assertEquals(sessionId(executor.launches[0]), sessionId(executor.launches[1]))
    }

    @Test
    fun `should run the CLI plainly for good when it refuses the stable session's flags`() = runBlocking {
        val executor = FakeCLIExecutor {
            if ("--session-id" in it.args) CLIResult("error: unknown option '--session-id'", 1) else CLIResult(usageScreen, 0)
        }
        val runner = runner(stableCall(), executor)

        runner.run()
        runner.run()

        assertEquals(
            listOf(
                listOf("/usage", "--allowed-tools", "", "--session-id", sessionId(executor.launches[0]) ?: "", "--name", "ClaudeBar Probe"),
                listOf("/usage", "--allowed-tools", ""),
                listOf("/usage", "--allowed-tools", ""),
            ),
            executor.launches,
        )
    }

    @Test
    fun `should read a stable session's id and resume phrases from the definition and write them back`() {
        val call = decode("""{"cli":"claude","session":{"id":{"stable":"ClaudeBar Probe"},"create":["--session-id","{{id}}"],"resume":["--resume","{{id}}"],"resumeOn":["already in use"]}}""")

        assertEquals(CLICall.Session.Id(stable = "ClaudeBar Probe"), call.session?.id)
        assertEquals(listOf("already in use"), call.session?.resumeOn)
        assertEquals(call, decode(encode(call)))
    }
}
