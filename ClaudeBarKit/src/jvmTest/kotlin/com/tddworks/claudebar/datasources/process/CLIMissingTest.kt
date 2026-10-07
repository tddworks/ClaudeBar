package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.ErrorFact
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * A CLI that isn't on this Mac is `cliNotFound` — the fact that lets a login read as *not set
 * up* rather than failing (#198) — not the terminal runner's own error ("Couldn't connect").
 */
class CLIMissingTest {
    @Test
    fun `should report a CLI that isn't installed as missing, not as a failed connection (#198)`() = runBlocking {
        val executor = FakeCLIExecutor { throw UsageError.CliNotFound("acme") }
        val fetcher = CLIFetcher(CLICall(cli = "acme", args = listOf("/usage")), { executor }, { "/dedicated" })

        val failure = assertThrows<CLIMissingError> { runBlocking { fetcher.fetch(null) } }

        assertEquals(ErrorFact.CliMissing, failure.fact)
        assertEquals(UsageError.CliNotFound("acme"), failure.reason)
    }

    @Test
    fun `should report the CLI as not found when it isn't on this Mac`() {
        // A host where no login shell answers and no install folder holds it.
        val executor = DefaultCLIExecutor(fakeHost())

        val failure = assertThrows<UsageError.CliNotFound> {
            runBlocking { executor.execute("claudebar-no-such-cli", emptyList(), null, 1.0, null, emptyMap()) }
        }

        assertEquals(UsageError.CliNotFound("claudebar-no-such-cli"), failure)
    }
}
