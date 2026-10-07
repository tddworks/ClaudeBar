package com.tddworks.claudebar.datasources.logs

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import platform.Foundation.NSProcessInfo
import platform.Foundation.NSTemporaryDirectory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The macOS side of usage history against the real system: NSCalendar's days, NSDateFormatter, stat and a seeked read. */
class LogPlatformTest {
    @Test
    fun `should start a day at local midnight in the calendar's time zone`() {
        val shanghai = localCalendar("Asia/Shanghai")
        // 2026-05-28T03:00:00Z is 11:00 in Shanghai; its day began at 2026-05-27T16:00:00Z.
        assertEquals(1_779_897_600.0, shanghai.startOfDay(1_779_937_200.0))
        assertEquals(1_779_984_000.0, shanghai.addingDays(1, 1_779_897_600.0))
    }

    @Test
    fun `should read a written-out date in its zone and no date the format doesn't give back`() {
        assertEquals(1_779_926_400.0, formattedSeconds("2026-05-28", "yyyy-MM-dd", "UTC"))
        assertNull(formattedSeconds("2026-02-30", "yyyy-MM-dd", "UTC"))
    }

    @Test
    fun `should stamp a file and read it from an offset`() {
        val path = NSTemporaryDirectory() + NSProcessInfo.processInfo.globallyUniqueString + ".jsonl"
        SystemFileSystem.sink(Path(path)).buffered().use { it.writeString("first\nsecond\n") }
        try {
            val stamp = assertNotNull(fileStamp(path))
            assertEquals(13L, stamp.size)
            assertTrue(stamp.inode != 0L)
            assertEquals("second\n", fileSource(path, 6).buffered().use { it.readString() })
        } finally {
            SystemFileSystem.delete(Path(path))
        }
    }
}
