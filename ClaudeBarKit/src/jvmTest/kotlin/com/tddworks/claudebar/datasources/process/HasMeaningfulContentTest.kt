package com.tddworks.claudebar.datasources.process

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** When a capture has shown something — the `hasMeaningfulContent` suite of the Swift runner tests. */
class HasMeaningfulContentTest {
    private val host = fakeHost()
    private val runner = InteractiveRunner(host.terminals, host.locator, host.machine, host.files)

    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }
    private fun text(value: String) = value.encodeToByteArray()

    @Test
    fun `should treat no output as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(ByteArray(0)))
    }

    @Test
    fun `should treat blank space as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(text("   \n\t\r\n  ")))
    }

    @Test
    fun `should treat visible text as the CLI having shown something`() {
        assertTrue(runner.hasMeaningfulContent(text("Hello, World!")))
    }

    @Test
    fun `should treat a lone style reset as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x5B, 0x30, 0x6D)))
    }

    @Test
    fun `should treat showing the cursor as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68)))
    }

    @Test
    fun `should treat a run of terminal controls as the CLI having shown nothing yet`() {
        val controls = bytes(0x1B, 0x5B, 0x30, 0x6D) + bytes(0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68) + bytes(0x1B, 0x5B, 0x32, 0x4A)

        assertFalse(runner.hasMeaningfulContent(controls))
    }

    @Test
    fun `should treat character-set switches as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x28, 0x42) + bytes(0x1B, 0x28, 0x30)))
    }

    @Test
    fun `should treat a window title ending in a bell as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x5D) + text("0;Window Title") + bytes(0x07)))
    }

    @Test
    fun `should treat a window title ending in a string terminator as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x5D) + text("0;Window Title") + bytes(0x1B, 0x5C)))
    }

    @Test
    fun `should treat a multi-line window title ending in a bell as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x5D) + text("0;Line1\nLine2\nLine3") + bytes(0x07)))
    }

    @Test
    fun `should treat a multi-line window title ending in a string terminator as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x5D) + text("0;Line1\nLine2\nLine3") + bytes(0x1B, 0x5C)))
    }

    @Test
    fun `should treat styled visible text as the CLI having shown something`() {
        val styled = bytes(0x1B, 0x5B, 0x30, 0x6D) + text("Hello") + bytes(0x1B, 0x5B, 0x31, 0x6D) + text("World")

        assertTrue(runner.hasMeaningfulContent(styled))
    }

    @Test
    fun `should treat text after a window title as the CLI having shown something`() {
        assertTrue(runner.hasMeaningfulContent(bytes(0x1B, 0x5D) + text("0;Title") + bytes(0x07) + text("Actual content")))
    }

    @Test
    fun `should treat text among every kind of terminal control as the CLI having shown something`() {
        val mixed = bytes(0x1B, 0x5D) + text("0;Title") + bytes(0x07) +
            bytes(0x1B, 0x5B, 0x30, 0x6D) +
            bytes(0x1B, 0x28, 0x42) +
            text("Usage: 50%") +
            bytes(0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68)

        assertTrue(runner.hasMeaningfulContent(mixed))
    }

    @Test
    fun `should treat bytes that aren't text as the CLI having shown something`() {
        assertTrue(runner.hasMeaningfulContent(bytes(0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81)))
    }

    @Test
    fun `should treat no bytes at all as the CLI having shown nothing yet, before any decoding`() {
        assertFalse(runner.hasMeaningfulContent(ByteArray(0)))
    }

    @Test
    fun `should treat a lone escape character as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B)))
    }

    @Test
    fun `should treat several lone escape characters as the CLI having shown nothing yet`() {
        assertFalse(runner.hasMeaningfulContent(bytes(0x1B, 0x1B, 0x1B)))
    }

    @Test
    fun `should treat the bracket left by an unfinished terminal control as the CLI having shown something`() {
        // The ESC is stripped and "[" remains.
        assertTrue(runner.hasMeaningfulContent(bytes(0x1B, 0x5B)))
    }

    @Test
    fun `should treat the controls Claude's CLI writes before its screen as the CLI having shown nothing yet`() {
        val preamble = bytes(0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x6C) +
            bytes(0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x68) +
            bytes(0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68) +
            bytes(0x1B, 0x5B, 0x3F, 0x32, 0x30, 0x30, 0x34, 0x6C)

        assertFalse(runner.hasMeaningfulContent(preamble))
    }
}
