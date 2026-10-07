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
import platform.Security.SecRandomCopyBytes
import platform.Security.errSecSuccess
import platform.Security.kSecRandomDefault

/** The system's cryptographically secure generator, as CryptoKit's keys and Swift's `random` use. */
@OptIn(ExperimentalForeignApi::class)
internal class SystemRandomBytes : RandomBytes {
    override fun bytes(count: Int): ByteArray {
        val bytes = ByteArray(count)
        if (count == 0) return bytes
        val status = bytes.usePinned { SecRandomCopyBytes(kSecRandomDefault, count.toULong(), it.addressOf(0)) }
        check(status == errSecSuccess) { "The system's random source failed ($status)" }
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
