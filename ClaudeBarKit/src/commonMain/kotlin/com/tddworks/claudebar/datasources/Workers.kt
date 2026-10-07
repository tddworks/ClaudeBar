package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

// The workers' roles: DataSources.make picks one per case of a definition's closed sums.

internal interface CredentialFinding {
    /** null when nothing answered — *Key needed*. */
    fun find(): FoundCredential?
}

internal interface CredentialRefreshing {
    val retryStatuses: List<Int>
    /** Whether the renewed credential is ClaudeBar's to write back, or its owner wrote it and it is read again. */
    val writesBack: Boolean
    fun isDue(credential: Credential): Boolean
    suspend fun refresh(credential: Credential): Credential
}

internal interface Fetching {
    fun isReady(): Boolean
    suspend fun fetch(credential: Credential?): Response
}

internal interface Reading {
    fun read(response: Response, facts: MappingFacts, providerId: String): UsageSnapshot
}

/** A fix tried once when the mapping reports a failure; true when it changed something worth retrying for. */
internal interface Recovering {
    fun recover(): Boolean
}

/** A failure a worker reports as a fact, with the reason it gives when the definition says nothing. */
internal interface ReportedFailure {
    /** null when no definition may reword it — a 429 stays a rate limit. */
    val fact: ErrorFact?
    val reason: UsageError
}

/** A fact a worker reports about a failed fetch — the key of a data source's `errors`. */
internal sealed class ErrorFact {
    /** An HTTP status that is not an answer. 429 never is: it stays a rate limit. */
    data class HttpStatus(val status: Int) : ErrorFact()
    data object HttpOther : ErrorFact()
    data object CliMissing : ErrorFact()
    data object CliNonzero : ErrorFact()
    data object CliFailed : ErrorFact()

    /** The fact that covers this one when the definition doesn't name it. */
    val broader: ErrorFact? get() = if (this is HttpStatus) HttpOther else null

    val name: String
        get() = when (this) {
            is HttpStatus -> "http.$status"
            HttpOther -> "http.default"
            CliMissing -> "cli.missing"
            CliNonzero -> "cli.nonzero"
            CliFailed -> "cli.failed"
        }

    companion object {
        fun parse(name: String): ErrorFact? = when (name) {
            "http.default" -> HttpOther
            "cli.missing" -> CliMissing
            "cli.nonzero" -> CliNonzero
            "cli.failed" -> CliFailed
            else -> name.removePrefix("http.").toIntOrNull()
                ?.takeIf { name.startsWith("http.") && it in 100..599 && it != 429 }
                ?.let(::HttpStatus)
        }
    }
}

/** An HTTP answer outside 2xx, kept with its status so a refresh can be tried. */
internal class HTTPStatusError(val status: Int, override val reason: UsageError) :
    Exception("HTTP $status"), ReportedFailure {
    override val fact: ErrorFact? get() = if (reason is UsageError.RateLimited) null else ErrorFact.HttpStatus(status)
}

/** The last usage and a rate limit's end, kept between refreshes. */
internal class UsageMemory {
    private val lock = SynchronizedObject()
    private var last: Pair<UsageSnapshot, Double>? = null
    private var retryAt: Double? = null

    fun snapshot(withinSeconds: Double, nowSeconds: Double): UsageSnapshot? = synchronized(lock) {
        last?.takeIf { nowSeconds - it.second < withinSeconds }?.first
    }

    fun remember(usage: UsageSnapshot, atSeconds: Double) = synchronized(lock) { last = usage to atSeconds }

    fun rateLimit(nowSeconds: Double): Double? = synchronized(lock) {
        retryAt?.takeIf { it > nowSeconds } ?: run { retryAt = null; null }
    }

    fun rememberRateLimit(untilSeconds: Double) = synchronized(lock) { retryAt = untilSeconds }
}
