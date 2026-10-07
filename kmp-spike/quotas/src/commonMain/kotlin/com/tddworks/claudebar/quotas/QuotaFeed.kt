package com.tddworks.claudebar.quotas

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The edge the platform implements: Swift fetches (CLI, Keychain, URLSession); Kotlin decides. */
interface QuotaSource {
    suspend fun fetch(): List<Quota>
}

/**
 * Exercises SKIE's two headline bridges: a `suspend fun` (→ Swift `async`) and a
 * `StateFlow` (→ Swift `AsyncSequence`).
 */
class QuotaFeed(private val source: QuotaSource, private val policy: StatusPolicy) {
    private val _overall = MutableStateFlow(QuotaStatus.HEALTHY)
    val overall: StateFlow<QuotaStatus> = _overall.asStateFlow()

    suspend fun refresh(nowMillis: Long): QuotaStatus {
        val status = source.fetch().overallStatus(policy, nowMillis)
        _overall.value = status
        return status
    }

    fun statuses(): Flow<QuotaStatus> = overall
}
