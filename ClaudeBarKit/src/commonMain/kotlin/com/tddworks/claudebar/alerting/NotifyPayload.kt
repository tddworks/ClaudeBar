package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.UsageQuota

/**
 * One login's quota window with the name the lineup gives it — read off the monitor by the
 * caller, so the builder never reaches into an account.
 */
internal data class NotifyQuotaReading(
    val providerId: String,
    val providerName: String,
    val quota: UsageQuota,
)

/** Which window the widget gauge shows; either half empty means "whichever needs attention most". */
internal data class NotifyGaugeSelection(
    val providerId: String = "",
    val quotaKey: String = "",
) {
    val isAutomatic: Boolean get() = providerId.isEmpty() || quotaKey.isEmpty()

    companion object {
        val automatic = NotifyGaugeSelection()
    }
}

/**
 * Everything ClaudeBar wants standing on the phone right now. Compared by value, so an
 * unchanged quota costs no request. A null surface is one the person turned off — left alone,
 * not cleared. [screenTile] is the same tile as [tile] (the gateway takes one body on both
 * routes) but switched and published on its own.
 */
internal data class NotifyPayload(
    val tile: NotifyTile? = null,
    val gauge: NotifyGauge? = null,
    val screenTile: NotifyTile? = null,
) {
    /** Nothing to say, so nothing to send. */
    val isEmpty: Boolean get() = tile == null && gauge == null && screenTile == null

    companion object {
        val empty = NotifyPayload()
    }
}
