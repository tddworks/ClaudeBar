package com.tddworks.claudebar.domain.provider

import com.tddworks.claudebar.domain.model.UsageSnapshot

/**
 * Protocol defining how to probe for usage data.
 * This is an internal implementation detail - callers use AIProvider.refresh() instead.
 */
interface UsageProbe {
    /**
     * Fetches the current usage snapshot
     */
    suspend fun probe(): UsageSnapshot

    /**
     * Checks if the probe is available (CLI installed, credentials present, etc.)
     */
    suspend fun isAvailable(): Boolean
}
