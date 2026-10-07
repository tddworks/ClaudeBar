package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.mapping.ErrorRef
import com.tddworks.claudebar.datasources.process.FakeCLIExecutor
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/** A worker reports a fact; the data source's `errors` says what it means. */
class ErrorFactsTest {
    private fun decode(errors: String, fetch: String = """{"http":{"url":"https://acme.test/usage"}}"""): DataSourceDefinition =
        definition("""
        {"kind":"api","fetch":$fetch,"mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}},
         "errors":$errors}
        """)

    private fun make(definition: DataSourceDefinition, status: Int, headers: Map<String, String> = emptyMap()): DataSource =
        testDataSources(network = AnsweringNetwork.answering("{}", status, headers)).make(definition, "acme")

    private suspend fun reason(source: DataSource): UsageError? = (thrown { source.fetchUsage() } as? DataSourceError)?.reason

    @Test
    fun `should give the reason the definition names for an HTTP status`() = runTest {
        val source = make(decode("""{"http.404":"subscriptionRequired"}"""), 404)
        assertEquals(UsageError.SubscriptionRequired, reason(source))
    }

    @Test
    fun `should give the definition's default reason for any other failing HTTP status`() = runTest {
        val source = make(decode("""{"http.default":{"executionFailed":"Acme is down"}}"""), 502)
        assertEquals(UsageError.ExecutionFailed("Acme is down"), reason(source))
    }

    @Test
    fun `should name the HTTP status when no rule in the definition covers it`() = runTest {
        val source = make(decode("""{"http.404":"noData"}"""), 500)
        assertEquals(UsageError.ExecutionFailed("HTTP error: 500"), reason(source))
    }

    @Test
    fun `should stay rate limited on a 429 whatever the definition's default says`() = runTest {
        val source = make(decode("""{"http.default":{"executionFailed":"busy"}}"""), 429, mapOf("Retry-After" to "60"))
        assertEquals(UsageError.RateLimited(TEST_NOW + 60), reason(source))
    }

    @Test
    fun `should take a status the request accepts as an answer, not a failure`() = runTest {
        val definition = decode("{}", """{"http":{"url":"https://acme.test/usage","acceptedStatuses":[200,404]}}""")
        val response = make(definition, 404).fetchResponse()
        assertEquals(404, response.status)
    }

    @Test
    fun `should stay rate limited on a 429 even when the request lists it as accepted`() = runTest {
        val definition = decode("{}", """{"http":{"url":"https://acme.test/usage","acceptedStatuses":[200,429]}}""")
        val source = make(definition, 429, mapOf("Retry-After" to "30"))
        assertEquals(UsageError.RateLimited(TEST_NOW + 30), reason(source))
    }

    @ParameterizedTest
    @ValueSource(strings = ["""{"http.429":"noData"}""", """{"http.abc":"noData"}""", """{"cli.exit":"noData"}"""])
    fun `should reject a definition naming an unknown error or its own rule for a 429`(errors: String) {
        assertThrows<DefinitionError> { decode(errors) }
    }

    @Test
    fun `should give the definition's reason when the CLI exits with an error`() = runTest {
        val executor = FakeCLIExecutor("/usr/local/bin/acme") { CLIResult("", exitCode = 3) }
        val definition = decode("""{"cli.nonzero":{"sessionExpired":"Run acme login."}}""", """{"command":{"cli":"acme"}}""")
        val source = testDataSources(cli = executor).make(definition, "acme")

        val reason = reason(source)

        assertEquals(UsageError.SessionExpired("Run acme login."), reason)
        assertEquals("Run acme login.", (reason as? UsageError.SessionExpired)?.hint)
    }

    @Test
    fun `should keep the error rules when the definition is written out and read back`() {
        val definition = decode("""{"http.404":"noData","cli.missing":{"cliNotFound":"acme"}}""")
        assertEquals(mapOf(ErrorFact.HttpStatus(404) to ErrorRef.NoData, ErrorFact.CliMissing to ErrorRef.CliNotFound("acme")), definition.errors)
        assertEquals(definition, DataSourceDefinition.from(definition.toJson()))
    }
}
