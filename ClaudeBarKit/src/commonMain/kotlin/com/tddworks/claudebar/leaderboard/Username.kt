package com.tddworks.claudebar.leaderboard

/**
 * *USERNAME* — the name on the board, chosen at join and shown publicly. An invalid name can't
 * be held at all; whether it is free is the server's to answer. The rule is pinned by
 * `Tests/DomainTests/Leaderboard/vectors.json`, which the Worker checks too.
 */
@ConsistentCopyVisibility
internal data class Username private constructor(val value: String) {
    override fun toString() = "@$value"

    companion object {
        private const val ALLOWED = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"

        /** The name, or null when it breaks the rule. */
        fun of(text: String): Username? =
            if (text.length in 3..20 && text.all { it in ALLOWED }) Username(text) else null
    }
}
