package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import platform.Foundation.NSProcessInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** The adapters the Swift app had as `Foundation.Process` wrappers, against the real system. */
class ProcessAdaptersTest {
    @Test
    fun `should answer a JSON-RPC line over a CLI's standard input and output`() = runBlocking {
        val transport = MacProcesses.transports.open("/bin/cat", emptyList(), null, null)
        try {
            transport.send("""{"id":1}""".encodeToByteArray())

            assertEquals("""{"id":1}""", transport.receive().decodeToString())
        } finally {
            transport.close()
        }
    }

    @Test
    fun `should say the CLI is not found before starting a JSON-RPC pipe to it`() {
        assertFailsWith<UsageError.CliNotFound> { MacProcesses.transports.open("claudebar-no-such-cli", emptyList(), null, null) }
    }

    @Test
    fun `should fail a JSON-RPC receive once the CLI has gone`() = runBlocking {
        val transport = MacProcesses.transports.open("/usr/bin/true", emptyList(), null, null)
        try {
            assertFailsWith<UsageError.ExecutionFailed> { transport.receive() }
        } finally {
            transport.close()
        }
        Unit
    }

    @Test
    fun `should give a login's exit status`() = runBlocking {
        assertEquals(0, PosixSignInProcess.run("/usr/bin/true", emptyList(), emptyMap(), "/tmp", 10.0))
        assertEquals(1, PosixSignInProcess.run("/usr/bin/false", emptyList(), emptyMap(), "/tmp", 10.0))
    }

    @Test
    fun `should stop a login that outlasts its time`() = runBlocking {
        assertFailsWith<SignInError.TimedOut> {
            PosixSignInProcess.run("/bin/sleep", listOf("30"), emptyMap(), "/tmp", 0.5)
        }
        Unit
    }

    @Test
    fun `should list this test's own executable among the running processes`() {
        val own = NSProcessInfo.processInfo.arguments.first().toString()

        assertTrue(SystemRunningProcesses.executablePaths().any { it.endsWith(own.substringAfterLast('/')) })
    }

    @Test
    fun `should make the dedicated folder CLIs run in`() {
        val folder = MacProcesses.host.directory(com.tddworks.claudebar.datasources.WorkingDirectory.DEDICATED)

        assertTrue(folder.endsWith("/ClaudeBar/Probe"))
        assertTrue(MacFiles.exists(folder))
    }
}
