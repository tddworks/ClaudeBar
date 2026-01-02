package com.tddworks.claudebar.domain.monitor

import com.tddworks.claudebar.domain.model.QuotaStatus
import com.tddworks.claudebar.domain.model.UsageQuota
import com.tddworks.claudebar.domain.model.UsageSnapshot
import com.tddworks.claudebar.domain.provider.AIProvider
import com.tddworks.claudebar.domain.provider.AIProviderRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * The main domain service that coordinates quota monitoring across AI providers.
 * Providers are rich domain models that own their own snapshots.
 * QuotaMonitor coordinates refreshes and alerts users when status changes.
 */
class QuotaMonitor(
    private val providers: AIProviderRepository,
    private val alerter: QuotaAlerter? = null
) {
    /** Previous status for change detection */
    private val previousStatuses = mutableMapOf<String, QuotaStatus>()

    /** Current monitoring job */
    private var monitoringJob: Job? = null

    /** Whether monitoring is active */
    private val _isMonitoring = MutableStateFlow(false)
    val isMonitoring: StateFlow<Boolean> = _isMonitoring.asStateFlow()

    /** The currently selected provider ID (for UI display) */
    private val _selectedProviderId = MutableStateFlow("claude")
    val selectedProviderId: StateFlow<String> = _selectedProviderId.asStateFlow()

    init {
        selectFirstEnabledIfNeeded()
    }

    // MARK: - Monitoring Operations

    /**
     * Refreshes all enabled providers concurrently.
     * Each provider updates its own snapshot.
     * Disabled providers are skipped.
     */
    suspend fun refreshAll() {
        coroutineScope {
            providers.enabled.forEach { provider ->
                launch {
                    refreshProvider(provider)
                }
            }
        }
    }

    /** Refreshes a single provider */
    private suspend fun refreshProvider(provider: AIProvider) {
        if (!provider.isAvailable()) {
            return
        }

        try {
            val snapshot = provider.refresh()
            handleSnapshotUpdate(provider, snapshot)
        } catch (e: Throwable) {
            // Provider stores error in lastError - no need for external observer
        }
    }

    /** Handles snapshot update and alerts user if status changed */
    private suspend fun handleSnapshotUpdate(provider: AIProvider, snapshot: UsageSnapshot) {
        val previousStatus = previousStatuses[provider.id] ?: QuotaStatus.HEALTHY
        val newStatus = snapshot.overallStatus

        previousStatuses[provider.id] = newStatus

        // Alert user only if status changed
        if (previousStatus != newStatus) {
            alerter?.alert(
                providerId = provider.id,
                previousStatus = previousStatus,
                currentStatus = newStatus
            )
        }
    }

    /** Refreshes a single provider by its ID */
    suspend fun refresh(providerId: String) {
        val provider = providers.provider(providerId) ?: return
        refreshProvider(provider)
    }

    /** Refreshes all enabled providers except the specified one */
    suspend fun refreshOthers(exceptProviderId: String) {
        val otherProviders = providers.enabled.filter { it.id != exceptProviderId }

        coroutineScope {
            otherProviders.forEach { provider ->
                launch {
                    refreshProvider(provider)
                }
            }
        }
    }

    // MARK: - Queries

    /** Returns the provider with the given ID */
    fun provider(id: String): AIProvider? = providers.provider(id)

    /** Returns all providers */
    val allProviders: List<AIProvider>
        get() = providers.all

    /** Returns only enabled providers */
    val enabledProviders: List<AIProvider>
        get() = providers.enabled

    /** Adds a provider dynamically */
    fun addProvider(provider: AIProvider) {
        providers.add(provider)
    }

    /** Removes a provider by ID */
    fun removeProvider(id: String) {
        providers.remove(id)
    }

    /** Returns the lowest quota across all enabled providers */
    fun lowestQuota(): UsageQuota? =
        providers.enabled
            .mapNotNull { it.snapshot.value?.lowestQuota }
            .minByOrNull { it.percentRemaining }

    /** Returns the overall status across enabled providers (worst status wins) */
    val overallStatus: QuotaStatus
        get() = providers.enabled
            .mapNotNull { it.snapshot.value?.overallStatus }
            .maxByOrNull { it.severity } ?: QuotaStatus.HEALTHY

    // MARK: - Selection

    /** The currently selected provider (from enabled providers) */
    val selectedProvider: AIProvider?
        get() = providers.enabled.find { it.id == _selectedProviderId.value }

    /** Status of the currently selected provider (for menu bar icon) */
    val selectedProviderStatus: QuotaStatus
        get() = selectedProvider?.snapshot?.value?.overallStatus ?: QuotaStatus.HEALTHY

    /** Whether any provider is currently refreshing */
    val isRefreshing: Boolean
        get() = providers.all.any { it.isSyncing.value }

    /** Selects a provider by ID (must be enabled) */
    fun selectProvider(id: String) {
        if (providers.enabled.any { it.id == id }) {
            _selectedProviderId.value = id
        }
    }

    /**
     * Sets a provider's enabled state.
     * When disabling the currently selected provider, automatically switches
     * to the first available enabled provider.
     */
    fun setProviderEnabled(id: String, enabled: Boolean) {
        val provider = providers.provider(id) ?: return
        provider.isEnabled = enabled
        if (!enabled) {
            selectFirstEnabledIfNeeded()
        }
    }

    /**
     * Selects the first enabled provider if current selection is invalid.
     * Called automatically during initialization and when providers are disabled.
     */
    private fun selectFirstEnabledIfNeeded() {
        if (providers.enabled.none { it.id == _selectedProviderId.value }) {
            providers.enabled.firstOrNull()?.let {
                _selectedProviderId.value = it.id
            }
        }
    }

    // MARK: - Continuous Monitoring

    /**
     * Starts continuous monitoring at the specified interval.
     * Returns a Flow of monitoring events.
     */
    fun startMonitoring(interval: Duration = 60.seconds): Flow<MonitoringEvent> {
        // Stop any existing monitoring
        monitoringJob?.cancel()

        _isMonitoring.value = true

        return flow {
            while (true) {
                refreshAll()
                emit(MonitoringEvent.Refreshed)
                delay(interval)
            }
        }
    }

    /** Stops continuous monitoring */
    fun stopMonitoring() {
        _isMonitoring.value = false
        monitoringJob?.cancel()
        monitoringJob = null
    }
}
