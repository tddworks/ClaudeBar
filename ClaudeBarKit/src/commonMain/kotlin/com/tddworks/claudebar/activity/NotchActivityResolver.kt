package com.tddworks.claudebar.activity

import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.UsageQuota

/**
 * Decides what, if anything, the notch shows now. Pure — state in, one activity or nothing
 * out — so every rule about what wins the notch is here, and the window stays presentation.
 */
public class NotchActivityResolver(
    /** How long a finished session keeps the notch before it retracts. */
    private val finishedDisplayDurationSeconds: Double = DEFAULT_FINISHED_DISPLAY_DURATION_SECONDS,
) {
    /**
     * The single activity worth showing, or null to stay hidden.
     *
     * [sessions] are live and recently finished ones, ClaudeBar's own runs already filtered
     * out; [headlineQuota] is the quota the person chose to watch, null before the first
     * refresh; [nowSeconds] lets the "done" flash expire deterministically.
     */
    fun resolve(
        sessions: List<Session>,
        quotas: List<UsageQuota>,
        headlineQuota: UsageQuota?,
        nowSeconds: Double,
    ): NotchActivity? {
        val candidates = sessions.mapNotNull { activity(it, nowSeconds) }.toMutableList()
        mostDepletedQuotaNeedingAttention(quotas)?.let { candidates += NotchActivity.QuotaThreshold(it) }
        headlineQuota?.let { candidates += NotchActivity.QuotaGlance(it) }

        val topSeverity = candidates.maxOfOrNull { it.severity } ?: return null
        // Among equals the one waiting longest wins: blocked ten minutes beats ten seconds.
        return candidates.filter { it.severity == topSeverity }.reduce { winner, next ->
            val left = next.session
            val right = winner.session
            if (left != null && right != null && left.startedAtSeconds < right.startedAtSeconds) next else winner
        }
    }

    private fun activity(session: Session, nowSeconds: Double): NotchActivity? = when (session.phase) {
        Session.Phase.AWAITING_INPUT -> NotchActivity.AwaitingInput(session)
        Session.Phase.SUBAGENTS_WORKING -> NotchActivity.AgentsWorking(session)
        Session.Phase.ACTIVE -> NotchActivity.Working(session)
        Session.Phase.STOPPED, Session.Phase.ENDED -> {
            val finishedAt = session.finishedAtSeconds
            if (finishedAt != null && nowSeconds - finishedAt < finishedDisplayDurationSeconds) {
                NotchActivity.Finished(session)
            } else {
                null
            }
        }
    }

    /**
     * Only critical and depleted quotas take over the notch: warning is real but not urgent,
     * and a notch that lights up at half a tank stops meaning anything.
     */
    private fun mostDepletedQuotaNeedingAttention(quotas: List<UsageQuota>): UsageQuota? = quotas
        .filter {
            when (QuotaStatus.from(it.percentRemaining)) {
                QuotaStatus.CRITICAL, QuotaStatus.DEPLETED -> true
                QuotaStatus.HEALTHY, QuotaStatus.WARNING -> false
            }
        }
        .minByOrNull { it.percentRemaining }

    companion object {
        const val DEFAULT_FINISHED_DISPLAY_DURATION_SECONDS: Double = 4.0
    }
}
