package com.tddworks.claudebar.datasources

import java.io.File
import java.util.TimeZone

// The JVM runs tests only (MODULAR_DESIGN §9).
internal actual fun modifiedSeconds(path: String): Double? =
    File(path).takeIf { it.exists() }?.lastModified()?.let { it / 1000.0 }

internal actual fun platformTimeZone(): String = TimeZone.getDefault().id

internal actual fun platformOsVersion(): String = System.getProperty("os.version") ?: "0.0.0"
