package com.tddworks.claudebar.providers

/** Guest passes a plan lets the person hand out — each gives a friend a free week of the product. */
@ConsistentCopyVisibility
public data class GuestPass private constructor(
    /** The passes left; null when unknown. */
    val passesRemaining: Long?,
    /** The referral link to share. */
    val referralURL: String,
) {
    /** Whether there are passes to share; an unknown count might still have some. */
    val hasPassesAvailable: Boolean get() = passesRemaining?.let { it > 0 } ?: true

    val displayText: String
        get() = when (val count = passesRemaining) {
            null -> "Share Claude Code"
            0L -> "No passes left"
            1L -> "1 pass left"
            else -> "$count passes left"
        }

    companion object {
        /** A count below zero is none. */
        operator fun invoke(passesRemaining: Long? = null, referralURL: String) =
            GuestPass(passesRemaining?.let { maxOf(0, it) }, referralURL)

        /** A pass to share; a count below zero is none. */
        fun of(passesRemaining: Long?, referralURL: String): GuestPass = invoke(passesRemaining, referralURL)
    }
}

/** Where a provider's guest passes come from — the definition's CLI, run by the engine. */
internal interface GuestPassSource {
    /** Whether passes can be read here (the CLI exists). */
    suspend fun isAvailable(): Boolean

    /** Reads the guest passes. */
    suspend fun fetch(): GuestPass
}
