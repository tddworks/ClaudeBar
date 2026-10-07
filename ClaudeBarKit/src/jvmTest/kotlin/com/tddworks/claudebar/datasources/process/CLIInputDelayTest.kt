package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLICall
import com.tddworks.claudebar.datasources.DefinitionJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** A TUI that redraws after its startup paint discards what was typed sooner, so a `cli` call can wait first. */
class CLIInputDelayTest {
    private val makeExecutor = CLIFetcher.system(fakeHost())

    private fun decode(json: String) = DefinitionJson.decodeFromString(CLICall.serializer(), json)

    @Test
    fun `should wait the stated delay before typing into the CLI`() {
        val call = decode("""{"cli":"tool","input":"/usage","inputDelay":1.5}""")

        assertEquals(1.5, call.inputDelay)
        assertEquals(1.5, (makeExecutor(call) as DefaultCLIExecutor).inputDelay)
    }

    @Test
    fun `should wait the terminal's default four tenths of a second when no delay is stated`() {
        val call = decode("""{"cli":"tool"}""")

        assertNull(call.inputDelay)
        assertEquals(0.4, (makeExecutor(call) as DefaultCLIExecutor).inputDelay)
    }

    @Test
    fun `should keep the input delay when the definition is written out and read back`() {
        val call = CLICall(cli = "tool", input = "/usage", inputDelay = 1.5)

        assertEquals(call, decode(DefinitionJson.encodeToString(CLICall.serializer(), call)))
    }
}
