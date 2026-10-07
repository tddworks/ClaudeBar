package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.StatusPolicy
import com.tddworks.claudebar.quotas.UsageQuota
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/**
 * Turns quota readings into the tile and gauge published to Notify! — the whole decision
 * layer of the feature, pure, with "now" a parameter. The rules:
 * 1. The worst quota leads: by status, then by how little is left; the tile takes its color and bar.
 * 2. The tile carries up to six windows as a metrics row — the gateway's ceiling.
 * 3. Labels drop the provider name when one provider reports them all ("5h  7d").
 * 4. Percentages are remaining, so a full bar is a full quota.
 */
internal class NotifyPayloadBuilder(
    /** Names the sending app, not the quota: the gateway treats a title as an identity. */
    private val title: String = DEFAULT_TITLE,
) {
    fun payload(
        readings: List<NotifyQuotaReading>,
        nowSeconds: Double,
        gaugeSelection: NotifyGaugeSelection = NotifyGaugeSelection.automatic,
        includesTile: Boolean = true,
        includesGauge: Boolean = true,
        includesScreenTile: Boolean = true,
        statusPolicy: StatusPolicy = StatusPolicy.Absolute,
    ): NotifyPayload {
        val ordered = ordered(readings, statusPolicy, nowSeconds)
        val headline = ordered.firstOrNull() ?: return NotifyPayload.empty

        // Built once and shared: the gateway takes one body on both routes, and two builds could drift.
        val tile = if (includesTile || includesScreenTile) tile(ordered, headline, statusPolicy, nowSeconds) else null

        return NotifyPayload(
            tile = if (includesTile) tile else null,
            gauge = if (includesGauge) gauge(ordered, headline, gaugeSelection, statusPolicy, nowSeconds) else null,
            screenTile = if (includesScreenTile) tile else null,
        )
    }

    private fun tile(
        ordered: List<NotifyQuotaReading>,
        headline: NotifyQuotaReading,
        policy: StatusPolicy,
        now: Double,
    ): NotifyTile? {
        val omitsProviderName = ordered.map { it.providerId }.toSet().size == 1
        val metrics = ordered.take(NotifyLimits.METRIC_COUNT).mapNotNull { reading ->
            NotifyMetric(
                label = label(reading, omitsProviderName),
                value = headlineValue(reading.quota),
                unit = unit(reading.quota),
                tintHex = reading.quota.status(policy, now).notifyTintHex,
            )
        }
        return NotifyTile(
            title = title,
            body = summary(headline, now),
            symbolName = NotifySymbol.QUOTA,
            tintHex = headline.quota.status(policy, now).notifyTintHex,
            progress = progress(ordered),
            trailing = headline.quota.compactResetTime(now),
            metrics = metrics,
        )
    }

    private fun gauge(
        ordered: List<NotifyQuotaReading>,
        headline: NotifyQuotaReading,
        selection: NotifyGaugeSelection,
        policy: StatusPolicy,
        now: Double,
    ): NotifyGauge? {
        val shown = selected(ordered, selection) ?: headline
        return NotifyGauge(
            title = title,
            value = headlineValue(shown.quota),
            unit = unit(shown.quota),
            detail = gaugeDetail(shown, now),
            symbolName = NotifySymbol.QUOTA,
            tintHex = shown.quota.status(policy, now).notifyTintHex,
            progress = if (shown.quota.isDollarBased) null else shown.quota.percentRemaining,
        )
    }

    companion object {
        const val DEFAULT_TITLE = "ClaudeBar"

        /**
         * Worst first, and total: equal readings must build equal payloads, or the driver would
         * republish forever. Display names aren't unique (an aggregating provider can report two
         * accounts under one name), so the provider id breaks the last tie.
         */
        fun ordered(
            readings: List<NotifyQuotaReading>,
            policy: StatusPolicy = StatusPolicy.Absolute,
            nowSeconds: Double,
        ): List<NotifyQuotaReading> = readings.sortedWith(
            compareByDescending<NotifyQuotaReading> { it.quota.status(policy, nowSeconds) }
                .thenBy { it.quota.percentRemaining }
                .thenBy { it.providerName }
                .thenBy { it.quota.quotaType.quotaKey }
                .thenBy { it.providerId },
        )

        /** The reading the person pinned, or null when automatic or no longer reporting. */
        fun selected(readings: List<NotifyQuotaReading>, selection: NotifyGaugeSelection): NotifyQuotaReading? {
            if (selection.isAutomatic) return null
            return readings.firstOrNull {
                it.providerId == selection.providerId && it.quota.quotaType.quotaKey == selection.quotaKey
            }
        }

        /** "Claude 5h", or "5h" when the tile covers one provider. */
        fun label(reading: NotifyQuotaReading, omittingProviderName: Boolean): String {
            val window = windowLabel(reading.quota)
            return if (omittingProviderName) window else "${reading.providerName} $window"
        }

        /** The quota's own short title when its data source set one, else "5h", "7d". */
        fun windowLabel(quota: UsageQuota): String = quota.compactTitle ?: quota.quotaType.shortLabel

        /** A bare whole percentage, or the balance for a quota measured in money. */
        fun headlineValue(quota: UsageQuota): String =
            formattedBalance(quota) ?: "${roundedHalfAway(quota.percentRemaining)}"

        fun unit(quota: UsageQuota): String? = if (quota.isDollarBased) null else "%"

        /** "Claude 5h, 42% left, resets in 2:14" — the body, shown only without metrics, so it carries the number. */
        fun summary(reading: NotifyQuotaReading, nowSeconds: Double): String {
            val parts = mutableListOf("${reading.providerName} ${windowLabel(reading.quota)}")
            parts += formattedBalance(reading.quota)?.let { "$it left" }
                ?: "${roundedHalfAway(reading.quota.percentRemaining)}% left"
            reading.quota.compactResetTime(nowSeconds)?.let { parts += resets(it) }
            return parts.joinToString(", ")
        }

        /** "Claude 5h, resets in 2:14" — beside a headline that already shows the percentage. */
        fun gaugeDetail(reading: NotifyQuotaReading, nowSeconds: Double): String {
            val parts = mutableListOf("${reading.providerName} ${windowLabel(reading.quota)}")
            reading.quota.compactResetTime(nowSeconds)?.let { parts += resets(it) }
            return parts.joinToString(", ")
        }

        /** The tile's bar falls through a money headline to the worst quota with a percentage. */
        fun progress(ordered: List<NotifyQuotaReading>): Double? =
            ordered.firstOrNull { !it.quota.isDollarBased }?.quota?.percentRemaining

        private fun resets(compact: String): String = if (compact == "soon") "resets soon" else "resets in $compact"

        /** Swift's `rounded()`: halves away from zero. */
        private fun roundedHalfAway(value: Double): Int =
            (if (value >= 0) floor(value + 0.5) else ceil(value - 0.5)).toInt()

        /** "$2.10", "¥110.00" — the card's `formattedDollarRemaining`; null for a percentage quota. */
        private fun formattedBalance(quota: UsageQuota): String? {
            val nanos = quota.dollarRemainingNanos ?: return null
            val symbol = quota.currency?.let { UsageQuota.currencySymbol(it) } ?: "$"
            val cents = (abs(nanos) + 5_000_000) / 10_000_000
            val sign = if (nanos < 0 && cents > 0) "-" else ""
            return "$symbol$sign${cents / 100}.${(cents % 100).toString().padStart(2, '0')}"
        }
    }
}
