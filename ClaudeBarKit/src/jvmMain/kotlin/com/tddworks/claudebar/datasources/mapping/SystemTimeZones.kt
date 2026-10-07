package com.tddworks.claudebar.datasources.mapping

import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone

internal actual fun systemTimeZones(): TimeZones = JvmTimeZones

/** java.time's zone rules — the JVM runs tests only. */
private object JvmTimeZones : TimeZones {
    override val current: String get() = TimeZone.getDefault().id

    override fun offsetSeconds(zone: String, atSeconds: Double): Int? = runCatching {
        ZoneId.of(zone).rules.getOffset(Instant.ofEpochSecond(kotlin.math.floor(atSeconds).toLong())).totalSeconds
    }.getOrNull()
}
