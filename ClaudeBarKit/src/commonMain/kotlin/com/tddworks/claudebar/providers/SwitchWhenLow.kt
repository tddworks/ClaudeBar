package com.tddworks.claudebar.providers

import kotlinx.coroutines.flow.StateFlow

/**
 * *Switch when low* — the opt-in policy that moves new sessions off a login that is running
 * out: below [below] percent left, to the ticked login with the most left. Off until the
 * person turns it on; every login is ticked until they untick it. Kept in the provider's own settings.
 */
internal class SwitchWhenLow internal constructor(
    private val providerId: String,
    private val settings: ProviderSettingsRepository,
) {
    private data class Policy(val isOn: Boolean, val below: Int, val skipped: Set<String>)

    private val state = ObservableState(
        Policy(
            isOn = settings.isOn(ON_KEY, providerId) ?: false,
            below = settings.value(BELOW_KEY, providerId)?.toIntOrNull() ?: 10,
            skipped = (settings.value(SKIP_KEY, providerId) ?: "").split(',').filter { it.isNotEmpty() }.toSet(),
        ),
    )

    /** Bumped after every change to the policy. */
    val revision: StateFlow<Long> get() = state.revision

    var isOn: Boolean
        get() = state.current.isOn
        set(value) {
            state.update { it.copy(isOn = value) }
            settings.setOn(value, ON_KEY, providerId)
        }

    /** The percentage left below which new sessions move. */
    var below: Int
        get() = state.current.below
        set(value) {
            state.update { it.copy(below = value) }
            settings.setValue(value.toString(), BELOW_KEY, providerId)
        }

    /** Whether new sessions may move to [account]. */
    fun mayPick(account: Account): Boolean = account.accountId !in state.current.skipped

    fun setMayPick(allowed: Boolean, account: Account) {
        val skipped = state.update { it.copy(skipped = if (allowed) it.skipped - account.accountId else it.skipped + account.accountId) }.skipped
        settings.setValue(if (skipped.isEmpty()) null else skipped.sorted().joinToString(","), SKIP_KEY, providerId)
    }

    /** Where new sessions should move from [current], among [logins] — null when the policy is off, [current] has room, or no ticked login has more left. */
    fun next(current: Account, logins: List<Account>): Account? {
        val left = current.percentLeft
        if (!isOn || left == null || left >= below.toDouble()) return null
        return logins.filter { it !== current && it.isEnabled && mayPick(it) && (it.percentLeft ?: -1.0) > left }
            .maxByOrNull { it.percentLeft ?: -1.0 }
    }

    private companion object {
        const val ON_KEY = "switchWhenLow"
        const val BELOW_KEY = "switchWhenLowBelow"
        const val SKIP_KEY = "switchWhenLowSkip"
    }
}
