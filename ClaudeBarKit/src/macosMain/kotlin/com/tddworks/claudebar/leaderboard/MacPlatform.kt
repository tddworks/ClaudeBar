package com.tddworks.claudebar.leaderboard

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.darwin.Darwin
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSDate
import platform.Foundation.NSTimeZone
import platform.Foundation.NSURLRequestReloadIgnoringLocalCacheData
import platform.Foundation.dateWithTimeIntervalSince1970
import platform.Foundation.localTimeZone
import platform.posix.arc4random_buf

/**
 * The system's cryptographically secure generator (arc4random, the kernel's CSPRNG — the one
 * Swift's `random` uses). Not `Security`: only `storage` uses that framework (MODULAR_DESIGN §3).
 */
@OptIn(ExperimentalForeignApi::class)
internal class SystemRandomBytes : RandomBytes {
    override fun bytes(count: Int): ByteArray {
        val bytes = ByteArray(count)
        if (count == 0) return bytes
        bytes.usePinned { arc4random_buf(it.addressOf(0), count.toULong()) }
        return bytes
    }
}

/** The Mac's current time zone, read at each instant so a change of zone or daylight saving is followed. */
internal class SystemUtcOffset : UtcOffset {
    override fun secondsAt(unixSeconds: Double): Long =
        NSTimeZone.localTimeZone.secondsFromGMTForDate(NSDate.dateWithTimeIntervalSince1970(unixSeconds))
}

/** URLSession under Ktor, never answering from its cache: the app reads the board fresh. */
internal fun leaderboardHttpEngine(): HttpClientEngine = Darwin.create {
    configureRequest { setCachePolicy(NSURLRequestReloadIgnoringLocalCacheData) }
}
