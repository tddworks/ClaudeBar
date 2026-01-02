package com.tddworks.claudebar.domain.model

/**
 * Represents Claude guest passes that can be shared with friends.
 * Each pass gives the recipient a free week of Claude Code.
 */
data class ClaudePass(
    /** The number of guest passes remaining (null if unknown) */
    val passesRemaining: Int? = null,

    /** The referral URL to share with friends */
    val referralURL: String
) {
    init {
        // Ensure passes remaining is not negative
        require(passesRemaining == null || passesRemaining >= 0) {
            "passesRemaining must be non-negative"
        }
    }

    /**
     * Whether there are passes available to share.
     * Returns true if count is unknown (we assume there might be passes).
     */
    val hasPassesAvailable: Boolean
        get() = passesRemaining?.let { it > 0 } ?: true

    /**
     * Human-readable display text for the pass count.
     */
    val displayText: String
        get() = when (val count = passesRemaining) {
            null -> "Share Claude Code"
            0 -> "No passes left"
            1 -> "1 pass left"
            else -> "$count passes left"
        }
}
