package com.tddworks.claudebar.datasources.logs

import kotlinx.io.RawSource
import kotlinx.io.asSource
import java.io.FileInputStream
import java.nio.file.Files
import java.nio.file.attribute.FileTime
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.math.floor

// The JVM runs tests only (MODULAR_DESIGN §9).

private fun zone(id: String?): ZoneId =
    id?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.systemDefault()

private fun instant(seconds: Double): Instant {
    val whole = floor(seconds)
    return Instant.ofEpochSecond(whole.toLong(), ((seconds - whole) * 1e9).toLong())
}

private fun seconds(instant: Instant): Double = instant.epochSecond + instant.nano / 1e9

internal actual fun localCalendar(timeZone: String?): LocalCalendar {
    val zone = zone(timeZone)
    return object : LocalCalendar {
        override fun startOfDay(atSeconds: Double): Double =
            seconds(ZonedDateTime.ofInstant(instant(atSeconds), zone).toLocalDate().atStartOfDay(zone).toInstant())

        override fun addingDays(days: Int, toSeconds: Double): Double =
            seconds(ZonedDateTime.ofInstant(instant(toSeconds), zone).plusDays(days.toLong()).toInstant())
    }
}

internal actual fun formattedSeconds(text: String, format: String, timeZone: String?): Double? {
    val formatter = runCatching { SimpleDateFormat(format, Locale.US) }.getOrNull() ?: return null
    formatter.timeZone = TimeZone.getTimeZone(zone(timeZone))
    val date = formatter.parse(text, ParsePosition(0)) ?: return null
    return if (formatter.format(date) == text) date.time / 1000.0 else null
}

internal actual fun fileStamp(path: String): FileStamp? = runCatching {
    val attributes = Files.readAttributes(java.nio.file.Path.of(path), "unix:ino,size,lastModifiedTime,ctime")
    FileStamp(
        inode = (attributes["ino"] as Number).toLong(),
        size = (attributes["size"] as Number).toLong(),
        modifiedNanos = (attributes["lastModifiedTime"] as FileTime).to(TimeUnit.NANOSECONDS),
        changedNanos = (attributes["ctime"] as FileTime).to(TimeUnit.NANOSECONDS),
    )
}.getOrNull()

internal actual fun fileSource(path: String, offset: Long): RawSource {
    val stream = FileInputStream(path)
    stream.channel.position(offset)
    return stream.asSource()
}
