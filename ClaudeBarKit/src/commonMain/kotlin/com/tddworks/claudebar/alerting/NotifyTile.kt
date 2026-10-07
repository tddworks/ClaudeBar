package com.tddworks.claudebar.alerting

/** One cell of a Live Activity metrics row, e.g. "5h 42%"; up to six sit where the body would. */
@ConsistentCopyVisibility
internal data class NotifyMetric private constructor(
    val label: String,
    val value: String,
    val unit: String?,
    val tintHex: String?,
) {
    companion object {
        /** Null when the label or value is empty after cleaning, since the gateway needs both. */
        operator fun invoke(label: String, value: String, unit: String? = null, tintHex: String? = null): NotifyMetric? {
            val cleanLabel = NotifyLimits.text(label, NotifyLimits.METRIC_LABEL_LENGTH) ?: return null
            val cleanValue = NotifyLimits.text(value, NotifyLimits.METRIC_VALUE_LENGTH) ?: return null
            return NotifyMetric(
                cleanLabel,
                cleanValue,
                NotifyLimits.text(unit, NotifyLimits.METRIC_UNIT_LENGTH),
                NotifyLimits.tint(tintHex),
            )
        }
    }
}

/**
 * The Live Activity tile on the Lock Screen — and, unchanged, the Home Screen widget. The
 * gateway has no tile type: the fields present decide the layout, so a title, a bar and a
 * metrics row IS the metrics layout. Every field is cleaned on the way in.
 */
@ConsistentCopyVisibility
internal data class NotifyTile private constructor(
    /** The tile's identity; the one field a start cannot omit. */
    val title: String,
    /** Second line, shown only when there are no metrics. */
    val body: String?,
    val symbolName: String?,
    /** `#RRGGBB`, normally the worst status on show. */
    val tintHex: String?,
    /** 0–100: quota remaining, so a full bar is a full quota. */
    val progress: Double?,
    /** Static text where a timer would sit: the headline's compact reset countdown. */
    val trailing: String?,
    /** At most six; more are cut, not refused. */
    val metrics: List<NotifyMetric>,
) {
    companion object {
        operator fun invoke(
            title: String,
            body: String? = null,
            symbolName: String? = null,
            tintHex: String? = null,
            progress: Double? = null,
            trailing: String? = null,
            metrics: List<NotifyMetric> = emptyList(),
        ): NotifyTile? {
            val cleanTitle = NotifyLimits.text(title, NotifyLimits.TITLE_LENGTH) ?: return null
            return NotifyTile(
                cleanTitle,
                NotifyLimits.text(body, NotifyLimits.BODY_LENGTH),
                NotifyLimits.text(symbolName, NotifyLimits.SYMBOL_LENGTH),
                NotifyLimits.tint(tintHex),
                NotifyLimits.progress(progress),
                NotifyLimits.text(trailing, NotifyLimits.TRAILING_LENGTH),
                metrics.take(NotifyLimits.METRIC_COUNT),
            )
        }
    }
}
