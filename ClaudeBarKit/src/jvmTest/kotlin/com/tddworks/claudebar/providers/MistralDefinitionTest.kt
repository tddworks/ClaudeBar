package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** Mistral has no meter: its Vibe session logs are today's usage, shown as TODAY'S USAGE beside it. The definition only says Vibe is installed. */
class MistralDefinitionTest {
    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun make(withLogs: Boolean): Provider {
        if (withLogs) File(stub.home, ".vibe/logs/session/session_20260103_101500_abc").mkdirs()
        return stub.makeProvider("mistral")
    }

    @Test
    fun `should show Mistral with its console, off until the person turns it on`() {
        val provider = make(withLogs = true)
        assertEquals("Mistral", provider.name)
        assertFalse(provider.plainIsInLineup)
        assertEquals("https://console.mistral.ai", provider.plainDashboardURL)
    }

    @Test
    fun `should be available with no quota, never a made-up one, when Vibe has logs`() {
        val provider = make(withLogs = true)
        assertTrue(provider.isPlainAvailable())
        val usage = provider.refreshPlain().usage()
        assertTrue(usage.quotas.isEmpty())
        assertNull(usage.costUsage)
    }

    @Test
    fun `should be unavailable when Vibe is not installed`() {
        assertFalse(make(withLogs = false).isPlainAvailable())
    }
}
