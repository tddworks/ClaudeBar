package com.tddworks.claudebar.alerting

/**
 * The Notify! widget on the Lock Screen. `progress` is the gauge (a bar or a ring); `value` is
 * display text, so the phone never does arithmetic on it. Built only through [invoke], which
 * cleans every field, so a gauge that exists is one the gateway accepts.
 */
@ConsistentCopyVisibility
internal data class NotifyGauge private constructor(
    /** The widget's identity in the phone's picker; stable so switching quotas never renames it. */
    val title: String,
    /** Headline, e.g. "42". */
    val value: String?,
    /** Beside the value, e.g. "%". */
    val unit: String?,
    /** Quieter second line, e.g. "Claude 5h, resets in 2:14". */
    val detail: String?,
    val symbolName: String?,
    /** `#RRGGBB`, normally the shown quota's status. */
    val tintHex: String?,
    /** 0–100: quota remaining. */
    val progress: Double?,
) {
    companion object {
        /** Null only when the title is empty after cleaning; everything else shortens or drops. */
        operator fun invoke(
            title: String,
            value: String? = null,
            unit: String? = null,
            detail: String? = null,
            symbolName: String? = null,
            tintHex: String? = null,
            progress: Double? = null,
        ): NotifyGauge? {
            val cleanTitle = NotifyLimits.text(title, NotifyLimits.WIDGET_TITLE_LENGTH) ?: return null
            return NotifyGauge(
                cleanTitle,
                NotifyLimits.text(value, NotifyLimits.WIDGET_VALUE_LENGTH),
                NotifyLimits.text(unit, NotifyLimits.WIDGET_UNIT_LENGTH),
                NotifyLimits.text(detail, NotifyLimits.WIDGET_DETAIL_LENGTH),
                NotifyLimits.text(symbolName, NotifyLimits.SYMBOL_LENGTH),
                NotifyLimits.tint(tintHex),
                NotifyLimits.progress(progress),
            )
        }
    }
}
