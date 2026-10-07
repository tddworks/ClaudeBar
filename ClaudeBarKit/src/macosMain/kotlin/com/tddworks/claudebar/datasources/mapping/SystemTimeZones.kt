package com.tddworks.claudebar.datasources.mapping

import platform.Foundation.NSDate
import platform.Foundation.NSTimeZone
import platform.Foundation.dateWithTimeIntervalSince1970
import platform.Foundation.localTimeZone
import platform.Foundation.timeZoneWithName

internal actual fun systemTimeZones(): TimeZones = FoundationTimeZones

/** Foundation's zone rules, the ones `TimeZone(identifier:)` reads. */
private object FoundationTimeZones : TimeZones {
    override val current: String get() = NSTimeZone.localTimeZone.name

    override fun offsetSeconds(zone: String, atSeconds: Double): Int? =
        NSTimeZone.timeZoneWithName(zone)?.secondsFromGMTForDate(NSDate.dateWithTimeIntervalSince1970(atSeconds))?.toInt()
}
