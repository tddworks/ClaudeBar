package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.flow.StateFlow
import kotlin.coroutines.cancellation.CancellationException

/**
 * *Share Claude Code* — a provider's guest passes: invitation links its plan lets the person
 * hand out. An action, not usage, so it lives beside the provider's usage and never touches a
 * login's `lastError`.
 */
internal class GuestPasses(private val source: GuestPassSource) {
    private data class Seen(val pass: GuestPass? = null, val isFetching: Boolean = false, val error: UsageError? = null)

    private val state = ObservableState(Seen())

    /** Bumped after every change. */
    val revision: StateFlow<Long> get() = state.revision

    val pass: GuestPass? get() = state.current.pass
    val isFetching: Boolean get() = state.current.isFetching

    /** Separate from a login's `lastError`: a failed pass fetch never marks usage unavailable. */
    val error: UsageError? get() = state.current.error

    /** Offered only to a plan that can issue passes (#243). */
    fun isOffered(usage: UsageSnapshot?): Boolean = usage?.accountTier?.supportsGuestPasses == true

    suspend fun fetch(): Outcome<GuestPass> {
        state.update { it.copy(isFetching = true) }
        return try {
            val pass = source.fetch()
            state.update { it.copy(pass = pass, isFetching = false, error = null) }
            Outcome.Done(pass)
        } catch (cancelled: CancellationException) {
            state.update { it.copy(isFetching = false) }
            throw cancelled
        } catch (failure: Exception) {
            val error = failure.asUsageError()
            state.update { it.copy(isFetching = false, error = error) }
            Outcome.Refused(error.message ?: error.tag)
        }
    }

    fun clearError() {
        state.update { it.copy(error = null) }
    }
}
