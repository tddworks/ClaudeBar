package com.tddworks.claudebar.providers

import platform.Foundation.NSCalendar
import platform.Foundation.NSCalendarUnitDay
import platform.Foundation.NSCalendarUnitMonth
import platform.Foundation.NSCalendarUnitYear
import platform.Foundation.NSDate
import platform.Foundation.dateWithTimeIntervalSince1970

// The year, month and day the current calendar gives, as Swift's `Calendar.current` names a day.
internal actual fun localDayName(atSeconds: Double): String {
    val parts = NSCalendar.currentCalendar.components(
        NSCalendarUnitYear or NSCalendarUnitMonth or NSCalendarUnitDay,
        NSDate.dateWithTimeIntervalSince1970(atSeconds),
    )
    return "${parts.year.toString().padStart(4, '0')}-${parts.month.toString().padStart(2, '0')}-${parts.day.toString().padStart(2, '0')}"
}
