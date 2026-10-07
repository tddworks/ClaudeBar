package com.tddworks.claudebar.providers

import platform.AppKit.NSPasteboard
import platform.AppKit.NSPasteboardTypeString
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The pasteboard a CLI copies its link to — a private one here, so the person's clipboard is never touched. */
class SystemClipboardTest {
    private val pasteboard = NSPasteboard.pasteboardWithUniqueName()

    @AfterTest
    fun release() = pasteboard.releaseGlobally()

    @Test
    fun `should read the text a CLI copied`() {
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/referral/ABC", NSPasteboardTypeString)

        assertEquals("https://example.com/referral/ABC", SystemClipboard(pasteboard).text())
    }

    @Test
    fun `should read nothing when no text was copied`() {
        pasteboard.clearContents()

        assertNull(SystemClipboard(pasteboard).text())
    }
}
