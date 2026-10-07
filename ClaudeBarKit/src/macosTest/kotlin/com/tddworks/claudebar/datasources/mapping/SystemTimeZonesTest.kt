package com.tddworks.claudebar.datasources.mapping

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Foundation's zone rules, as HumanDate reads them on the Mac. */
class SystemTimeZonesTest {
    /** 2026-06-15 12:00:00 UTC. */
    private val now = 1_781_524_800.0

    @Test
    fun `should know how far a named zone is ahead of UTC on a given day`() {
        assertEquals(8 * 3600, systemTimeZones().offsetSeconds("Asia/Shanghai", now))
        assertEquals(-4 * 3600, systemTimeZones().offsetSeconds("America/New_York", now))
        assertNull(systemTimeZones().offsetSeconds("Nowhere/Atlantis", now))
    }

    @Test
    fun `should reset at the time a CLI gives in its own zone on the Mac`() {
        assertEquals(1_781_557_140.0, HumanDate.parse("Resets 4:59pm (America/New_York)", now))
    }
}
