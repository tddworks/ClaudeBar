package com.tddworks.claudebar.datasources.logs

import kotlinx.io.RawSource

/**
 * The local calendar a log's days are counted in — Swift's `Calendar`. Kotlin common has
 * none, so the platform answers: NSCalendar on macOS, java.time in tests.
 */
internal interface LocalCalendar {
    /** The start of the local day that holds [atSeconds]. */
    fun startOfDay(atSeconds: Double): Double

    /** [toSeconds] moved by [days] local days, keeping its time of day. */
    fun addingDays(days: Int, toSeconds: Double): Double
}

/** The calendar in [timeZone], or this Mac's own zone when it is null or unknown. */
internal expect fun localCalendar(timeZone: String? = null): LocalCalendar

/**
 * [text] read with a date [format] (Unicode pattern, en_US_POSIX) in [timeZone] — this Mac's
 * own when null or unknown. Text the format doesn't give back unchanged has no time.
 */
internal expect fun formattedSeconds(text: String, format: String, timeZone: String?): Double?

/** File metadata that changes whenever the file's content does; null when it can't be read. */
internal expect fun fileStamp(path: String): FileStamp?

/** The bytes of the file at [path] from [offset] on, without reading the ones before. Throws when it can't open. */
internal expect fun fileSource(path: String, offset: Long): RawSource

internal data class FileStamp(val inode: Long, val size: Long, val modifiedNanos: Long, val changedNanos: Long) {
    /**
     * Whether the stamp can tell two versions of a file apart. A filesystem that keeps
     * whole-second times could change a file twice with an identical stamp.
     */
    val isStrong: Boolean get() = inode != 0L && changedNanos % 1_000_000_000L != 0L
}
