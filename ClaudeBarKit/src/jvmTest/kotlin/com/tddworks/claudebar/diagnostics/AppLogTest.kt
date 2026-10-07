package com.tddworks.claudebar.diagnostics

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class AppLogTest {
    @TempDir
    lateinit var dir: File

    private val at = 1_791_357_113_616L // 2026-10-07T07:11:53.616Z

    private fun lines() = File(dir, "ClaudeBar.log").takeIf { it.exists() }?.readLines().orEmpty()

    @Test
    fun `should write a line with its time, level and category`() {
        FileLogSink(dir.path, nowMillis = { at }).write(LogLevel.INFO, "monitor", "Starting refresh")
        assertEquals(listOf("[2026-10-07T07:11:53.616Z] [INFO] [monitor] Starting refresh"), lines())
    }

    @Test
    fun `should keep debug lines out of the user's file`() {
        FileLogSink(dir.path, nowMillis = { at }).write(LogLevel.DEBUG, "probes", "noise")
        assertEquals(emptyList<String>(), lines())
    }

    @Test
    fun `should write a notice as info, as it always has`() {
        FileLogSink(dir.path, nowMillis = { at }).write(LogLevel.NOTICE, "ui", "opened")
        assertTrue(lines().single().contains("[INFO] [ui] opened"))
    }

    @Test
    fun `should start a new file and keep the last one once the file grows too big`() {
        val sink = FileLogSink(dir.path, maxBytes = 10, nowMillis = { at })
        sink.write(LogLevel.ERROR, "network", "first")
        sink.write(LogLevel.ERROR, "network", "second")
        assertTrue(File(dir, "ClaudeBar.old.log").readText().contains("first"))
        assertTrue(lines().single().endsWith("second"))
    }

    @Test
    fun `should send each category's lines to the installed sinks`() {
        val seen = mutableListOf<String>()
        AppLog.install(listOf(object : LogSink {
            override fun write(level: LogLevel, category: String, message: String) {
                seen += "$level $category $message"
            }
        }))
        AppLog.credentials.warning("Token loaded for provider")
        assertEquals(listOf("WARNING credentials Token loaded for provider"), seen)
        AppLog.install(emptyList())
    }

    @Test
    fun `should print a time before 1970 and in a leap year correctly`() {
        assertEquals("1969-12-31T23:59:59.999Z", isoTimestamp(-1))
        assertEquals("2024-02-29T12:00:00.000Z", isoTimestamp(1_709_208_000_000))
    }
}
