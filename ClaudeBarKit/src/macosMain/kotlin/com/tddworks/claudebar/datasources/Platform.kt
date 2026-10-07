package com.tddworks.claudebar.datasources

import platform.Foundation.NSDate
import platform.Foundation.NSFileManager
import platform.Foundation.NSFileModificationDate
import platform.Foundation.NSProcessInfo
import platform.Foundation.NSTimeZone
import platform.Foundation.localTimeZone
import platform.Foundation.timeIntervalSince1970

internal actual fun modifiedSeconds(path: String): Double? =
    (NSFileManager.defaultManager.attributesOfItemAtPath(path, null)?.get(NSFileModificationDate) as? NSDate)
        ?.timeIntervalSince1970

internal actual fun platformTimeZone(): String = NSTimeZone.localTimeZone.name

internal actual fun platformOsVersion(): String =
    NSProcessInfo.processInfo.operatingSystemVersionString.let { text ->
        Regex("""(\d+)\.(\d+)(?:\.(\d+))?""").find(text)?.destructured?.let { (major, minor, patch) ->
            "$major.$minor.${patch.ifEmpty { "0" }}"
        } ?: text
    }
