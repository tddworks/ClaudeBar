package com.tddworks.claudebar.monitoring

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class RefreshIntervalTest {
    @Test
    fun `should poll every 1, 5, 10 or 15 minutes, and never when refresh is off`() {
        assertNull(RefreshInterval.OFF.seconds)
        assertEquals(60, RefreshInterval.ONE_MINUTE.seconds)
        assertEquals(300, RefreshInterval.FIVE_MINUTES.seconds)
        assertEquals(600, RefreshInterval.TEN_MINUTES.seconds)
        assertEquals(900, RefreshInterval.FIFTEEN_MINUTES.seconds)
    }

    @Test
    fun `should refresh in the background for every option except off`() {
        assertFalse(RefreshInterval.OFF.isEnabled)
        assertTrue(RefreshInterval.ONE_MINUTE.isEnabled)
        assertTrue(RefreshInterval.FIVE_MINUTES.isEnabled)
        assertTrue(RefreshInterval.TEN_MINUTES.isEnabled)
        assertTrue(RefreshInterval.FIFTEEN_MINUTES.isEnabled)
    }

    @Test
    fun `should label each option as Settings' picker shows it`() {
        assertEquals("Off", RefreshInterval.OFF.label)
        assertEquals("1 min", RefreshInterval.ONE_MINUTE.label)
        assertEquals("5 min", RefreshInterval.FIVE_MINUTES.label)
        assertEquals("10 min", RefreshInterval.TEN_MINUTES.label)
        assertEquals("15 min", RefreshInterval.FIFTEEN_MINUTES.label)
    }

    @Test
    fun `should turn refresh off when the old background sync was disabled`() {
        assertEquals(RefreshInterval.OFF, RefreshInterval.migrating(enabled = false, storedSeconds = 60.0))
        assertEquals(RefreshInterval.OFF, RefreshInterval.migrating(enabled = false, storedSeconds = 900.0))
    }

    @Test
    fun `should move an old saved interval to the nearest offered one, never below one minute`() {
        // The retired 30s and 2m options, and anything under the floor, go up to 1 minute.
        assertEquals(RefreshInterval.ONE_MINUTE, RefreshInterval.migrating(enabled = true, storedSeconds = 30.0))
        assertEquals(RefreshInterval.ONE_MINUTE, RefreshInterval.migrating(enabled = true, storedSeconds = 60.0))
        assertEquals(RefreshInterval.ONE_MINUTE, RefreshInterval.migrating(enabled = true, storedSeconds = 120.0))
        assertEquals(RefreshInterval.FIVE_MINUTES, RefreshInterval.migrating(enabled = true, storedSeconds = 300.0))
        assertEquals(RefreshInterval.TEN_MINUTES, RefreshInterval.migrating(enabled = true, storedSeconds = 600.0))
        assertEquals(RefreshInterval.TEN_MINUTES, RefreshInterval.migrating(enabled = true, storedSeconds = 700.0))
        assertEquals(RefreshInterval.FIFTEEN_MINUTES, RefreshInterval.migrating(enabled = true, storedSeconds = 900.0))
    }

    @Test
    fun `should move the old 600-second default to ten minutes (#204)`() {
        assertEquals(RefreshInterval.TEN_MINUTES, RefreshInterval.migrating(enabled = true, storedSeconds = 600.0))
    }

    @Test
    fun `should offer the options in picker order, from off to fifteen minutes`() {
        assertEquals(
            listOf(RefreshInterval.OFF, RefreshInterval.ONE_MINUTE, RefreshInterval.FIVE_MINUTES, RefreshInterval.TEN_MINUTES, RefreshInterval.FIFTEEN_MINUTES),
            RefreshInterval.entries.toList(),
        )
    }
}
