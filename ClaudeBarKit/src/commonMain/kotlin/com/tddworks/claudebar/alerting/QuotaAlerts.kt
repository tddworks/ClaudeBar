package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.quotas.Left
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlin.math.floor

/** Where the person's alert percentages are kept — a destination's repository, never a provider setting. */
internal interface QuotaAlertSettingsRepository {
    /** Whole numbers 1–99. */
    fun quotaAlertPercents(): List<Int>
    fun setQuotaAlertPercents(percents: List<Int>)
}

/** Who needs to hear that a login fell below one of the person's percentages. */
internal interface QuotaAlertAnnouncer {
    suspend fun announce(alert: QuotaAlert)
}

/** *Claude · work is below 35% — 34% left*, as plain values. */
internal data class QuotaAlert(
    /** The login, as the lineup names it. */
    val login: String,
    /** The person's percentage it fell below. */
    val below: Int,
    /** What it has left, in whole percent. */
    val left: Int,
)

/**
 * *Quota alerts* (#68): the person's own percentages — *tell me below 35%* — beside the status
 * alerts at 20% and empty. After each refresh it says once that a login fell below one, and
 * again only after the login climbed back a point above it. The caller hands it each refresh
 * (the monitor knows nothing of it); [changed] is told when [percents] changes, for the UI.
 */
public class QuotaAlerts internal constructor(
    private val settings: QuotaAlertSettingsRepository,
    private val announcer: QuotaAlertAnnouncer,
    private val changed: () -> Unit = {},
) {
    /** Why a percentage wasn't added, in words Settings prints. */
    sealed class Refusal {
        abstract val message: String

        data object NotAPercent : Refusal() {
            override val message = "Enter a whole percent from 1 to 99."
        }

        data class AlreadyAlerted(val percent: Int) : Refusal() {
            override val message get() = "Already alerted — ClaudeBar tells you at $percent%."
        }

        data class AlreadyListed(val percent: Int) : Refusal() {
            override val message get() = "$percent% is already on the list."
        }

        data object Full : Refusal() {
            override val message = "Up to $MOST percentages."
        }
    }

    private val lock = SynchronizedObject()

    /** The person's percentages, highest first. */
    var percents: List<Int> = settings.quotaAlertPercents().sortedDescending()
        private set

    /**
     * Per login, the percentages it was told it fell below and hasn't climbed back from. In
     * memory: after a relaunch a login still below is told once more.
     */
    private val told = mutableMapOf<String, Set<Int>>()

    /** Adds what the person typed — `35` or `35%`; null when added, else why not. */
    fun add(entry: String): Refusal? {
        val digits = entry.trim { it == ' ' || it == '\t' || it.isSpaceSeparator() }.replace("%", "")
        val percent = digits.toIntOrNull()?.takeIf { it in 0..99 } ?: return Refusal.NotAPercent
        if (percent in ALREADY_ALERTED) return Refusal.AlreadyAlerted(percent)
        if (percent < 1) return Refusal.NotAPercent
        val refusal = synchronized(lock) {
            when {
                percent in percents -> Refusal.AlreadyListed(percent)
                percents.size >= MOST -> Refusal.Full
                else -> null.also { keep(percents + percent) }
            }
        }
        if (refusal == null) changed()
        return refusal
    }

    fun remove(percent: Int) {
        synchronized(lock) { keep(percents.filter { it != percent }) }
        changed()
    }

    /**
     * After a refresh: tells each percentage [login] just fell below. [usage] is what the
     * person sees — hidden quotas already left out; [name] is how the lineup names the login.
     */
    suspend fun review(login: String, name: String, usage: UsageSnapshot?) {
        val left = usage?.let(::lowestShare) ?: return
        val alerts = synchronized(lock) {
            val below = told[login].orEmpty().toMutableSet()
            val alerts = mutableListOf<QuotaAlert>()
            for (percent in percents) {
                if (left < percent) {
                    if (below.add(percent)) alerts += QuotaAlert(login = name, below = percent, left = floor(left).toInt())
                } else if (left >= percent + 1) {
                    below.remove(percent)
                }
            }
            told[login] = below
            alerts
        }
        for (alert in alerts) announcer.announce(alert)
    }

    private fun keep(list: List<Int>) {
        percents = list.sortedDescending()
        settings.setQuotaAlertPercents(percents)
    }

    companion object {
        /** How many percentages the person can keep. */
        const val MOST = 5

        /** Percentages the status alerts already say. */
        val ALREADY_ALERTED = setOf(20, 0)

        /** The lowest share left: a share as it is, money with a ceiling as its part of it; a bare balance has none. */
        private fun lowestShare(usage: UsageSnapshot): Double? = usage.quotas.mapNotNull { quota ->
            when (val left = quota.left) {
                is Left.Share -> left.percent
                is Left.Balance -> left.ceiling?.takeIf { it.amountNanos > 0 }
                    ?.let { left.remaining.amountNanos * 100.0 / it.amountNanos }
            }
        }.minOrNull()

        private fun Char.isSpaceSeparator(): Boolean = category == CharCategory.SPACE_SEPARATOR
    }
}
