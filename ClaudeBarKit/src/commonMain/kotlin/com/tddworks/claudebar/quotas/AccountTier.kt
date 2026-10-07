package com.tddworks.claudebar.quotas

/**
 * The account's plan, with a name and a badge.
 * Interim shape (CANONICAL_MODEL): becomes `Plan`; the Claude cases are vendor words that
 * don't belong in the kernel, and whether a plan issues guest passes is the definition's fact.
 */
sealed class AccountTier {
    /** Claude Max: session and weekly quotas, plus optional extra-usage cost. */
    data object ClaudeMax : AccountTier()

    /** Claude Pro: session and weekly quotas, plus optional extra-usage cost. */
    data object ClaudePro : AccountTier()

    /** Claude API: pay per use, cost only. */
    data object ClaudeApi : AccountTier()

    /** Any provider's own tier, by its badge ("PRO", "ULTRA"). */
    data class Custom(val badge: String) : AccountTier()

    val displayName: String
        get() = when (this) {
            ClaudeMax -> "Claude Max"
            ClaudePro -> "Claude Pro"
            ClaudeApi -> "API Usage"
            is Custom -> badge
        }

    val badgeText: String
        get() = when (this) {
            ClaudeMax -> "MAX"
            ClaudePro -> "PRO"
            ClaudeApi -> "API"
            is Custom -> badge
        }

    /** Only Max subscribers get Claude Code guest passes; offering them elsewhere can only fail (#243). */
    val supportsGuestPasses: Boolean get() = this == ClaudeMax
}
