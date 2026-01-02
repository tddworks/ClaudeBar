package com.tddworks.claudebar.domain.model

/**
 * Represents the account tier for any AI provider.
 * Supports both well-known tiers (Claude Max/Pro/API) and custom tiers from other providers.
 */
sealed class AccountTier {
    /** Claude Max subscription with session/weekly quotas + optional extra usage cost tracking */
    data object ClaudeMax : AccountTier()

    /** Claude Pro subscription with session/weekly quotas + optional extra usage cost tracking */
    data object ClaudePro : AccountTier()

    /** Claude API account with pay-per-use pricing (cost tracking only) */
    data object ClaudeApi : AccountTier()

    /** Custom tier for any provider (badge text, e.g., "PRO", "ULTRA") */
    data class Custom(val badge: String) : AccountTier()

    /** Display name for the account tier */
    val displayName: String
        get() = when (this) {
            is ClaudeMax -> "Claude Max"
            is ClaudePro -> "Claude Pro"
            is ClaudeApi -> "API Usage"
            is Custom -> badge
        }

    /** Short badge text for compact display */
    val badgeText: String
        get() = when (this) {
            is ClaudeMax -> "MAX"
            is ClaudePro -> "PRO"
            is ClaudeApi -> "API"
            is Custom -> badge
        }
}
