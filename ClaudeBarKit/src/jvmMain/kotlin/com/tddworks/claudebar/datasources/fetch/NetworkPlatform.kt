package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.NetworkClient
import java.time.Instant
import java.time.ZoneId

// The JVM runs tests only (MODULAR_DESIGN §9): tests hand a fetcher a fake or a MockEngine.
internal actual fun systemNetworkClient(): NetworkClient =
    throw UnsupportedOperationException("The JVM runs tests only; give the fetcher a NetworkClient")

internal actual fun insecureLocalhostNetworkClient(timeoutSeconds: Double): NetworkClient =
    throw UnsupportedOperationException("The JVM runs tests only; give the fetcher a NetworkClient")

internal actual fun startOfLocalDaySeconds(seconds: Double): Double {
    val zone = ZoneId.systemDefault()
    val day = Instant.ofEpochMilli((seconds * 1000).toLong()).atZone(zone).toLocalDate()
    return day.atStartOfDay(zone).toEpochSecond().toDouble()
}
