package com.tddworks.claudebar.activity

import com.tddworks.claudebar.providers.Account
import com.tddworks.claudebar.providers.InUseNotice
import com.tddworks.claudebar.providers.Provider

/**
 * *Alerting* for In use: who needs to hear that new sessions moved, or that a login is worth
 * moving to. A port of its own — quota alerts don't carry it.
 */
internal interface InUseAnnouncer {
    suspend fun announce(alert: InUseAlert)
}

/** *In use* news, as an alert carries it: plain values, and the `claudebar://use` link its button opens. */
internal data class InUseAlert(
    val kind: Kind,
    val providerName: String,
    val from: String,
    val to: String,
    /** What [from] has left, in whole percent. */
    val fromLeft: Int?,
    val toLeft: Int?,
    /** The button's link: back to [from] for a switch, on to [to] for a suggestion. */
    val link: String,
) {
    enum class Kind {
        /** *Switch when low* moved new sessions — the button undoes it. */
        SWITCHED,

        /** The login in use is low — the button moves new sessions. */
        WORTH_SWITCHING,
    }

    companion object {
        /** The alert for [notice] about [provider]'s logins. */
        operator fun invoke(notice: InUseNotice, provider: Provider): InUseAlert {
            val (kind, target) = when (notice) {
                is InUseNotice.Switched -> Kind.SWITCHED to notice.from
                is InUseNotice.WorthSwitching -> Kind.WORTH_SWITCHING to notice.to
            }
            val link = "claudebar://use?provider=${queryValue(provider.id)}&account=${queryValue(target.accountId)}"
            return InUseAlert(
                kind, provider.name, notice.from.displayName, notice.to.displayName,
                left(notice.from), left(notice.to), link,
            )
        }

        private fun left(account: Account): Int? = account.snapshot?.lowestQuota?.percentRemaining?.toInt()

        /** What a query value may hold as it is — as Foundation's `URLQueryItem` writes it; every other byte is escaped. */
        private const val KEPT = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$'()*+,;:@/?"

        private fun queryValue(text: String): String = buildString {
            for (byte in text.encodeToByteArray()) {
                val char = (byte.toInt() and 0xFF).toChar()
                if (byte >= 0 && char in KEPT) append(char)
                else append('%').append(HEX[(byte.toInt() shr 4) and 0xF]).append(HEX[byte.toInt() and 0xF])
            }
        }

        private const val HEX = "0123456789ABCDEF"
    }
}
