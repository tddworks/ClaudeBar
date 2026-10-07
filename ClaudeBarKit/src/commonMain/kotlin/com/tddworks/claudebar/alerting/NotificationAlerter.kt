package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.capitalizedWords
import kotlin.coroutines.cancellation.CancellationException

/**
 * How the lineup names a login ("Claude", "Codex · me@work"): its definition's profile name,
 * or an added account's. The composition root answers it from the providers; null when unknown.
 */
internal fun interface LineupNames {
    fun nameOf(providerId: String): String?
}

/** Tells the person, as a system notification, when a login's status gets worse: warning, critical, depleted. */
internal class NotificationAlerter(
    private val alertSender: AlertSender,
    private val names: LineupNames,
) {
    suspend fun requestPermission(): Boolean {
        AppLog.notifications.debug("Requesting alert permission...")
        val granted = alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: ${if (granted) "granted" else "denied"}")
        return granted
    }

    /** Called when a login's status changes; only a step worse is worth a notification. */
    suspend fun alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) {
        AppLog.notifications.debug("Status change: $providerId $previousStatus -> $currentStatus")
        if (currentStatus <= previousStatus) {
            AppLog.notifications.debug("Status improved or same, skipping alert")
            return
        }
        if (!shouldAlert(currentStatus)) {
            AppLog.notifications.debug("Status $currentStatus does not require alert")
            return
        }
        val providerName = providerDisplayName(providerId)
        AppLog.notifications.notice("Sending quota alert for $providerId: $currentStatus")
        try {
            alertSender.send("$providerName Quota Alert", alertBody(currentStatus, providerName), CATEGORY)
            AppLog.notifications.info("Alert sent successfully")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            AppLog.notifications.error("Failed to send alert: ${e.message}")
        }
    }

    fun shouldAlert(status: QuotaStatus): Boolean = status != QuotaStatus.HEALTHY

    /** The lineup's name, else the id capitalised. */
    fun providerDisplayName(providerId: String): String = names.nameOf(providerId) ?: providerId.capitalizedWords()

    fun alertBody(status: QuotaStatus, providerName: String): String = when (status) {
        QuotaStatus.WARNING -> "Your $providerName quota is running low. Consider pacing your usage."
        QuotaStatus.CRITICAL -> "Your $providerName quota is critically low! Save important work."
        QuotaStatus.DEPLETED -> "Your $providerName quota is depleted. Usage may be blocked."
        QuotaStatus.HEALTHY -> "Your $providerName quota has recovered."
    }

    companion object {
        const val CATEGORY = "QUOTA_ALERT"
    }
}
