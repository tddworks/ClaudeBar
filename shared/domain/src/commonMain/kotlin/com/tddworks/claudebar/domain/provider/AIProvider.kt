package com.tddworks.claudebar.domain.provider

import com.tddworks.claudebar.domain.model.UsageSnapshot
import kotlinx.coroutines.flow.StateFlow

/**
 * Interface defining what an AI provider is.
 * Each provider (Claude, Codex, Gemini) is a rich domain model implementing this interface.
 * Providers expose their state via StateFlows for reactive UI consumption.
 */
interface AIProvider {
    // MARK: - Identity

    /** Unique identifier for the provider (e.g., "claude", "codex", "gemini") */
    val id: String

    /** Display name for the provider (e.g., "Claude", "Codex", "Gemini") */
    val name: String

    /** CLI command used to invoke the provider */
    val cliCommand: String

    /** URL to the provider's usage/billing dashboard */
    val dashboardURL: String?

    /** URL to the provider's status page */
    val statusPageURL: String?
        get() = null

    /** Whether the provider is enabled (user can toggle this) */
    var isEnabled: Boolean

    // MARK: - State (Observable via StateFlow)

    /** Whether the provider is currently syncing data */
    val isSyncing: StateFlow<Boolean>

    /** The current usage snapshot (null if never refreshed or unavailable) */
    val snapshot: StateFlow<UsageSnapshot?>

    /** The last error that occurred during refresh */
    val lastError: StateFlow<Throwable?>

    // MARK: - Operations

    /**
     * Checks if the provider is available (CLI installed, credentials present, etc.)
     */
    suspend fun isAvailable(): Boolean

    /**
     * Refreshes the usage data and updates the snapshot.
     */
    suspend fun refresh(): UsageSnapshot
}
