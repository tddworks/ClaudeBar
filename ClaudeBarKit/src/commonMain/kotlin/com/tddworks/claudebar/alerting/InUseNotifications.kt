package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import kotlin.coroutines.cancellation.CancellationException

/**
 * *In use* news as a notification, with one button that opens its `claudebar://use` link:
 * *Use for New Sessions*, or *Undo* after a switch. The news arrives as plain values
 * ([News]): *In use* belongs to `activity`, which alerting may not name; the composition
 * root turns one into the other.
 */
internal class InUseNotifications(private val alertSender: AlertSender) {
    enum class Kind {
        /** *Switch when low* moved new sessions — the button undoes it. */
        SWITCHED,

        /** The login in use is low — the button moves new sessions. */
        WORTH_SWITCHING,
    }

    data class News(
        val kind: Kind,
        val providerName: String,
        val from: String,
        val to: String,
        /** What [from] has left, in whole percent. */
        val fromLeft: Int?,
        val toLeft: Int?,
        /** The button's link: back to [from] for a switch, on to [to] for a suggestion. */
        val link: String,
    )

    suspend fun announce(news: News) {
        fun left(value: Int?) = value?.let { " is at $it%" } ?: " is low"
        val (title, body, button) = when (news.kind) {
            Kind.WORTH_SWITCHING -> Triple(
                "${news.providerName}: ${news.from}${left(news.fromLeft)}",
                "${news.to} has ${news.toLeft?.let { "$it%" } ?: "more"} left. Start new terminal sessions on ${news.to}?",
                "Use for New Sessions",
            )
            Kind.SWITCHED -> Triple(
                "New ${news.providerName} sessions now use ${news.to}",
                "${news.from}${left(news.fromLeft)}. Sessions already running keep their login.",
                "Undo",
            )
        }
        try {
            alertSender.send(title, body, CATEGORY, button, news.link)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            AppLog.notifications.error("Failed to send the In use notification: ${e.message}")
        }
    }

    companion object {
        const val CATEGORY = "IN_USE"
    }
}
