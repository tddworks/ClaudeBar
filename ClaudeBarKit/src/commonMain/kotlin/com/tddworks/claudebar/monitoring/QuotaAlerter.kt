package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.quotas.QuotaStatus

/**
 * Tells the person a login's quota status changed. Monitoring may not use `alerting` (its
 * sibling), so the composition root adapts the notifications to this port.
 */
internal interface QuotaAlerter {
    /** Asks to send alerts; true when the person allows them. */
    suspend fun requestPermission(): Boolean

    /** A login's status changed; the implementation decides whether the person hears of it. */
    suspend fun alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus)
}
