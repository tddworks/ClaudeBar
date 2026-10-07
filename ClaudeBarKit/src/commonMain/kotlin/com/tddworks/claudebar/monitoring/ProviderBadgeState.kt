package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.providers.Account
import com.tddworks.claudebar.quotas.QuotaStatus

/**
 * What the popover header's badge says about a tab. No usage is its own state, apart from
 * usage that says all is well — a failed fetch used to show a green HEALTHY pill above a card
 * reading "Unavailable" (#259).
 */
public sealed class ProviderBadgeState {
    /** A refresh is in flight. */
    data object Syncing : ProviderBadgeState()

    /** The last fetch failed, so there are no numbers to show. */
    data object Unavailable : ProviderBadgeState()

    /** Nothing to read with yet — no CLI on this Mac, or no sign-in (#198). Waiting for the person, not failing. */
    data object NotSetUp : ProviderBadgeState()

    /** Waiting for setup, but its usage is read; the card says what the limits need, the header nothing (#198). */
    data object UsageOnly : ProviderBadgeState()

    /** No usage yet — first launch, or just enabled. */
    data object AwaitingData : ProviderBadgeState()

    /** There are numbers, and this is what they say. */
    data class Quota(val status: QuotaStatus) : ProviderBadgeState()

    /** Whether the header shows a badge at all — not while a login waiting for setup still shows its usage. */
    val showsBadge: Boolean get() = this != UsageOnly

    /** Whether this is real usage. */
    val hasData: Boolean get() = this is Quota

    /** What the badge reads of one login. */
    data class Login(
        val isSyncing: Boolean = false,
        val failed: Boolean = false,
        val needsSetup: Boolean = false,
        val readsUsage: Boolean = false,
    )

    companion object {
        /**
         * One provider's badge: syncing first; then the last usage's status, since stale numbers
         * beat none; then not set up (or usage only, when its usage is read); then unavailable
         * when the last fetch failed; else awaiting data.
         */
        fun from(
            isSyncing: Boolean,
            quotaStatus: QuotaStatus?,
            hasError: Boolean,
            needsSetup: Boolean = false,
            readsUsage: Boolean = false,
        ): ProviderBadgeState = when {
            isSyncing -> Syncing
            quotaStatus != null -> Quota(quotaStatus)
            needsSetup -> if (readsUsage) UsageOnly else NotSetUp
            hasError -> Unavailable
            else -> AwaitingData
        }

        /** A tab's badge from its logins: syncing when one is, failed or waiting for setup only when every one is, usage read when one reads it. */
        fun of(logins: List<Login>, quotaStatus: QuotaStatus?): ProviderBadgeState = from(
            isSyncing = logins.any { it.isSyncing },
            quotaStatus = quotaStatus,
            hasError = logins.isNotEmpty() && logins.all { it.failed },
            needsSetup = logins.isNotEmpty() && logins.all { it.needsSetup },
            readsUsage = logins.any { it.readsUsage },
        )

        /** A tab's badge, read from its accounts. */
        fun reading(accounts: List<Account>, quotaStatus: QuotaStatus?): ProviderBadgeState = of(
            accounts.map { Login(it.isSyncing, it.lastError != null, it.needsSetup, it.readsUsage) },
            quotaStatus,
        )
    }
}
