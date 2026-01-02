package com.tddworks.claudebar.domain.provider

import com.tddworks.claudebar.domain.model.UsageSnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Base implementation of AIProvider with common functionality.
 * Uses StateFlow for observable state (replaces Swift's @Observable).
 */
abstract class BaseAIProvider(
    override val id: String,
    override val name: String,
    override val cliCommand: String,
    override val dashboardURL: String? = null,
    override val statusPageURL: String? = null,
    private val probe: UsageProbe,
    private val settingsRepository: ProviderSettingsRepository
) : AIProvider {

    // MARK: - State (Observable via StateFlow)

    private val _isSyncing = MutableStateFlow(false)
    override val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _snapshot = MutableStateFlow<UsageSnapshot?>(null)
    override val snapshot: StateFlow<UsageSnapshot?> = _snapshot.asStateFlow()

    private val _lastError = MutableStateFlow<Throwable?>(null)
    override val lastError: StateFlow<Throwable?> = _lastError.asStateFlow()

    // MARK: - Enabled State

    private var _isEnabled: Boolean = settingsRepository.isEnabled(id)

    override var isEnabled: Boolean
        get() = _isEnabled
        set(value) {
            _isEnabled = value
            settingsRepository.setEnabled(value, id)
        }

    // MARK: - Operations

    override suspend fun isAvailable(): Boolean {
        return probe.isAvailable()
    }

    override suspend fun refresh(): UsageSnapshot {
        _isSyncing.value = true
        try {
            val newSnapshot = probe.probe()
            _snapshot.value = newSnapshot
            _lastError.value = null
            return newSnapshot
        } catch (e: Throwable) {
            _lastError.value = e
            throw e
        } finally {
            _isSyncing.value = false
        }
    }
}
