package com.tddworks.claudebar.domain.provider

import com.tddworks.claudebar.domain.model.ClaudePass
import com.tddworks.claudebar.domain.model.UsageSnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Interface for probing Claude guest passes.
 */
interface ClaudePassProbing {
    suspend fun isAvailable(): Boolean
    suspend fun probe(): ClaudePass
}

/**
 * Error type for pass-related operations.
 */
sealed class PassError : Exception() {
    data object ProbeNotConfigured : PassError() {
        private fun readResolve(): Any = ProbeNotConfigured
        override val message: String = "Guest pass probe is not configured"
    }
}

/**
 * Claude AI provider - a rich domain model.
 * Observable class with its own state (isSyncing, snapshot, error).
 * Owns its probe and manages its own data lifecycle.
 */
class ClaudeProvider(
    private val probe: UsageProbe,
    private val passProbe: ClaudePassProbing? = null,
    private val settingsRepository: ProviderSettingsRepository
) : BaseAIProvider(
    id = "claude",
    name = "Claude",
    cliCommand = "claude",
    dashboardURL = "https://console.anthropic.com/settings/billing",
    statusPageURL = "https://status.anthropic.com",
    probe = probe,
    settingsRepository = settingsRepository
) {
    // MARK: - Guest Pass State

    private val _guestPass = MutableStateFlow<ClaudePass?>(null)
    val guestPass: StateFlow<ClaudePass?> = _guestPass.asStateFlow()

    private val _isFetchingPasses = MutableStateFlow(false)
    val isFetchingPasses: StateFlow<Boolean> = _isFetchingPasses.asStateFlow()

    // MARK: - Guest Pass Operations

    /**
     * Whether guest passes feature is available.
     */
    val supportsGuestPasses: Boolean
        get() = passProbe != null

    /**
     * Fetches the current guest pass information.
     */
    suspend fun fetchPasses(): ClaudePass {
        val probing = passProbe ?: throw PassError.ProbeNotConfigured

        _isFetchingPasses.value = true
        try {
            val pass = probing.probe()
            _guestPass.value = pass
            return pass
        } finally {
            _isFetchingPasses.value = false
        }
    }
}
