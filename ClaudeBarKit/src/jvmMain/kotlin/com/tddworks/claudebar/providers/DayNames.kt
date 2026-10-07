package com.tddworks.claudebar.providers

import java.time.Instant
import java.time.ZoneId
import kotlin.math.floor

// The JVM runs tests only (MODULAR_DESIGN §9): the system zone stands in for this Mac's calendar.
internal actual fun localDayName(atSeconds: Double): String =
    Instant.ofEpochSecond(floor(atSeconds).toLong()).atZone(ZoneId.systemDefault()).toLocalDate().toString()
