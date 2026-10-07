package com.tddworks.claudebar.activity

import com.tddworks.claudebar.quotas.UsageQuota

/**
 * One thing the notch can say. Several sources compete for one strip of glass — sessions,
 * permission prompts, quota thresholds — so each is a case, and [NotchActivityResolver]
 * picks the winner without a view knowing the rules.
 *
 * Ordered by how loudly it demands attention, so two of the same kind compare equal
 * without being equal.
 */
public sealed class NotchActivity : Comparable<NotchActivity> {
    /** The session behind it, for the activities that have one. */
    open val session: Session? get() = null

    /** The quota behind it, for the activities that have one. */
    open val quota: UsageQuota? get() = null

    /**
     * Higher wins. A person being blocked beats anything a machine does, and a "done" flash
     * briefly interrupts ambient state without ever masking a blocked session.
     */
    internal abstract val severity: Int

    override fun compareTo(other: NotchActivity): Int = severity.compareTo(other.severity)

    /**
     * Nothing is happening, so the notch does ClaudeBar's job: how much of the watched quota
     * is left. The resting state, not an absence — a notch blank between sessions has no
     * reason to be on screen.
     */
    data class QuotaGlance(override val quota: UsageQuota) : NotchActivity() {
        override val severity: Int get() = 0
    }

    /** Claude Code is working on a turn. */
    data class Working(override val session: Session) : NotchActivity() {
        override val severity: Int get() = 1
    }

    /** Claude Code has fanned subagents out. */
    data class AgentsWorking(override val session: Session) : NotchActivity() {
        override val severity: Int get() = 2
    }

    /** A provider is at or past the point where the person should know. */
    data class QuotaThreshold(override val quota: UsageQuota) : NotchActivity() {
        override val severity: Int get() = 3
    }

    /** A turn or session just finished; transient (see [NotchActivityResolver]). */
    data class Finished(override val session: Session) : NotchActivity() {
        override val severity: Int get() = 4
    }

    /** Claude Code is blocked on the person. Outranks everything and never expires: only they can clear it. */
    data class AwaitingInput(override val session: Session) : NotchActivity() {
        override val severity: Int get() = 5
    }
}
