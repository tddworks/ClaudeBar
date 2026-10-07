package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.CLIResult
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CLIResultTest {
    @Test
    fun `should keep what the CLI printed and its exit code`() {
        val result = CLIResult("Hello, World!", 0)

        assertEquals("Hello, World!", result.output)
        assertEquals(0, result.exitCode)
    }

    @Test
    fun `should take the CLI as having succeeded when no exit code is given`() {
        val result = CLIResult("Success output")

        assertEquals("Success output", result.output)
        assertEquals(0, result.exitCode)
    }

    @Test
    fun `should keep the error the CLI printed and its failing exit code`() {
        val result = CLIResult("Error: command failed", 1)

        assertEquals("Error: command failed", result.output)
        assertEquals(1, result.exitCode)
    }

    @Test
    fun `should keep an empty answer when the CLI prints nothing`() {
        val result = CLIResult("", 0)

        assertTrue(result.output.isEmpty())
        assertEquals(0, result.exitCode)
    }

    @Test
    fun `should keep every line the CLI printed`() {
        val result = CLIResult("Line 1\nLine 2\nLine 3")

        assertTrue("Line 1" in result.output)
        assertTrue("Line 2" in result.output)
        assertTrue("Line 3" in result.output)
    }

    @Test
    fun `should treat two runs with the same output and exit code as the same`() {
        assertEquals(CLIResult("test", 0), CLIResult("test", 0))
    }

    @Test
    fun `should tell apart two runs that printed different output`() {
        assertNotEquals(CLIResult("test1", 0), CLIResult("test2", 0))
    }

    @Test
    fun `should tell apart two runs that exited differently`() {
        assertNotEquals(CLIResult("test", 0), CLIResult("test", 1))
    }
}
