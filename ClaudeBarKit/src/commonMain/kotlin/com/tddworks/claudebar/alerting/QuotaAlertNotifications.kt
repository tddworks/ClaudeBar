package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import kotlin.coroutines.cancellation.CancellationException

/** *Quota alerts* as a notification: *Claude · work is below 35%*, *34% left.* */
internal class QuotaAlertNotifications(private val alertSender: AlertSender) : QuotaAlertAnnouncer {
    override suspend fun announce(alert: QuotaAlert) {
        try {
            alertSender.send("${alert.login} is below ${alert.below}%", "${alert.left}% left.", CATEGORY)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            AppLog.notifications.error("Failed to send a quota alert: ${e.message}")
        }
    }

    companion object {
        const val CATEGORY = "QUOTA_ALERT_PERCENT"
    }
}
