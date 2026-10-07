package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlin.coroutines.cancellation.CancellationException

// Values cross, exceptions don't (MODULAR_DESIGN §5): a command the UI calls that can fail
// answers with one of these. Inside the SDK a refusal is still thrown, and turned into a value
// once, at the command.

/** What a command the person gave came to: done, or refused with the words Settings prints. */
public sealed class Outcome<out T> {
    data class Done<out T>(val value: T) : Outcome<T>()

    /** Nothing changed; [reason] says why, in the person's words. */
    data class Refused(val reason: String) : Outcome<Nothing>()

    /** The value when it was done, else null. */
    val valueOrNull: T? get() = (this as? Done)?.value

    /** Why it was refused, in the person's words; null when it was done. */
    val refusalOrNull: String? get() = (this as? Refused)?.reason
}

/** The command's result, or its refusal; cancellation still cancels. */
internal inline fun <T> outcome(command: () -> T): Outcome<T> = try {
    Outcome.Done(command())
} catch (cancelled: CancellationException) {
    throw cancelled
} catch (refused: Exception) {
    Outcome.Refused(refused.message ?: refused.toString())
}

/** What a refresh came to: the login's usage, or why there is none (its `lastError`). */
public sealed class RefreshOutcome {
    data class Refreshed(val usage: UsageSnapshot) : RefreshOutcome()

    data class Failed(val error: UsageError) : RefreshOutcome()

    val usageOrNull: UsageSnapshot? get() = (this as? Refreshed)?.usage
}

/** *Test Connection*: what came back, or the step that failed. */
public sealed class ConnectionOutcome {
    data class Answered(val response: Response) : ConnectionOutcome()

    data class Failed(val error: DataSourceError) : ConnectionOutcome()
}

/** Any failure as the reason a screen shows: a `UsageError` as it is, anything else as what it said. */
internal fun Throwable.asUsageError(): UsageError = when (this) {
    is UsageError -> this
    is DataSourceError -> reason
    else -> UsageError.ExecutionFailed(message ?: toString())
}
