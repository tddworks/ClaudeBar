package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.QuotaStatus

/**
 * The accent color sent to Notify! for a status: the Mac's four status colors
 * (`BaseTheme.defaultStatus*`) as hex, so a quota that looks critical in the menu bar looks
 * critical on the Lock Screen.
 */
internal val QuotaStatus.notifyTintHex: String
    get() = when (this) {
        QuotaStatus.HEALTHY -> "#59EBAD"
        QuotaStatus.WARNING -> "#FAB859"
        QuotaStatus.CRITICAL -> "#FA6B85"
        QuotaStatus.DEPLETED -> "#D94059"
    }

/** SF Symbols Notify! draws, named once so the tile and the widget cannot drift apart. */
internal object NotifySymbol {
    /** A gauge reads at both sizes and implies no direction of travel. */
    const val QUOTA = "gauge.with.needle"
}
