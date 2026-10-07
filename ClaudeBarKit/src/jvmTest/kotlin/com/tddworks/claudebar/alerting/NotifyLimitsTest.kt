package com.tddworks.claudebar.alerting

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class NotifyLimitsTest {

    // Text

    @Test
    fun `should send text to the phone without surrounding spaces`() {
        assertEquals("Claude 5h", NotifyLimits.text("  Claude 5h  ", maximum = 24))
    }

    @Test
    fun `should leave out the NUL character Notify! refuses`() {
        assertEquals("Claude 5h", NotifyLimits.text("Claude\u0000 5h", maximum = 24))
    }

    @Test
    fun `should shorten text that is too long rather than fail the publish`() {
        assertEquals("abcd", NotifyLimits.text("abcdefghij", maximum = 4))
    }

    @Test
    fun `should leave out empty text rather than send it blank`() {
        assertNull(NotifyLimits.text("", maximum = 24))
    }

    @Test
    fun `should leave out text that is only whitespace`() {
        assertNull(NotifyLimits.text("  \n\t ", maximum = 24))
    }

    @Test
    fun `should leave out text that is missing`() {
        assertNull(NotifyLimits.text(null, maximum = 24))
    }

    // Progress

    @Test
    fun `should show an empty bar when a quota is over its limit`() {
        assertEquals(0.0, NotifyLimits.progress(-12.0))
    }

    @Test
    fun `should show a full bar when a percentage is over one hundred`() {
        assertEquals(100.0, NotifyLimits.progress(140.0))
    }

    @Test
    fun `should show a percentage between zero and one hundred as it is`() {
        assertEquals(42.0, NotifyLimits.progress(42.0))
    }

    @Test
    fun `should send no bar when the percentage is missing`() {
        assertNull(NotifyLimits.progress(null))
    }

    @Test
    fun `should send no bar when the percentage is not a number or infinite`() {
        assertNull(NotifyLimits.progress(Double.NaN))
        assertNull(NotifyLimits.progress(Double.POSITIVE_INFINITY))
    }

    // Tint

    @Test
    fun `should send a six-digit hex color in uppercase with a leading hash`() {
        assertEquals("#59EBAD", NotifyLimits.tint("59ebad"))
        assertEquals("#59EBAD", NotifyLimits.tint("#59ebad"))
    }

    @Test
    fun `should send an eight-digit hex color in uppercase with a leading hash`() {
        assertEquals("#FF59EBAD", NotifyLimits.tint("ff59ebad"))
        assertEquals("#FF59EBAD", NotifyLimits.tint("#ff59ebad"))
    }

    @Test
    fun `should leave out a color with the wrong number of digits`() {
        assertNull(NotifyLimits.tint("#fff"))
        assertNull(NotifyLimits.tint("#1234567"))
    }

    @Test
    fun `should leave out a color with a character that is not hex`() {
        assertNull(NotifyLimits.tint("#59ebaz"))
    }
}
