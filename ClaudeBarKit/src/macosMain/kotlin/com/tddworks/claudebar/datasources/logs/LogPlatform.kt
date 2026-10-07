package com.tddworks.claudebar.datasources.logs

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.usePinned
import kotlinx.io.Buffer
import kotlinx.io.IOException
import kotlinx.io.RawSource
import platform.Foundation.NSCalendar
import platform.Foundation.NSCalendarUnitDay
import platform.Foundation.NSDate
import platform.Foundation.NSDateFormatter
import platform.Foundation.NSLocale
import platform.Foundation.NSTimeZone
import platform.Foundation.dateWithTimeIntervalSince1970
import platform.Foundation.localTimeZone
import platform.Foundation.timeIntervalSince1970
import platform.Foundation.timeZoneWithName
import platform.posix.SEEK_SET
import platform.posix.fclose
import platform.posix.fopen
import platform.posix.fread
import platform.posix.fseeko
import platform.posix.stat

private fun zone(name: String?): NSTimeZone =
    name?.let { NSTimeZone.timeZoneWithName(it) } ?: NSTimeZone.localTimeZone

internal actual fun localCalendar(timeZone: String?): LocalCalendar {
    val calendar = NSCalendar.currentCalendar.copy() as NSCalendar
    calendar.timeZone = zone(timeZone)
    return object : LocalCalendar {
        override fun startOfDay(atSeconds: Double): Double =
            calendar.startOfDayForDate(NSDate.dateWithTimeIntervalSince1970(atSeconds)).timeIntervalSince1970

        override fun addingDays(days: Int, toSeconds: Double): Double =
            calendar.dateByAddingUnit(NSCalendarUnitDay, days.toLong(), NSDate.dateWithTimeIntervalSince1970(toSeconds), 0u)
                ?.timeIntervalSince1970 ?: toSeconds
    }
}

internal actual fun formattedSeconds(text: String, format: String, timeZone: String?): Double? {
    val formatter = NSDateFormatter()
    formatter.locale = NSLocale(localeIdentifier = "en_US_POSIX")
    formatter.dateFormat = format
    formatter.timeZone = zone(timeZone)
    val date = formatter.dateFromString(text) ?: return null
    return if (formatter.stringFromDate(date) == text) date.timeIntervalSince1970 else null
}

internal actual fun fileStamp(path: String): FileStamp? = memScoped {
    val info = alloc<stat>()
    if (stat(path, info.ptr) != 0) return null
    FileStamp(
        inode = info.st_ino.toLong(),
        size = info.st_size,
        modifiedNanos = info.st_mtimespec.tv_sec * 1_000_000_000L + info.st_mtimespec.tv_nsec,
        changedNanos = info.st_ctimespec.tv_sec * 1_000_000_000L + info.st_ctimespec.tv_nsec,
    )
}

internal actual fun fileSource(path: String, offset: Long): RawSource {
    val file = fopen(path, "rb") ?: throw IOException("Can't open $path")
    if (fseeko(file, offset, SEEK_SET) != 0) {
        fclose(file)
        throw IOException("Can't seek in $path")
    }
    return object : RawSource {
        private val chunk = ByteArray(64 * 1024)

        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
            val wanted = minOf(byteCount, chunk.size.toLong()).toInt()
            if (wanted == 0) return 0
            val read = chunk.usePinned { fread(it.addressOf(0), 1u, wanted.toULong(), file).toInt() }
            if (read <= 0) return -1
            sink.write(chunk, 0, read)
            return read.toLong()
        }

        override fun close() {
            fclose(file)
        }
    }
}
