package com.tddworks.claudebar.domain.provider

/**
 * Repository interface for storing provider settings (e.g., isEnabled state).
 * Tests use mock implementations.
 * App uses platform-specific implementations (UserDefaults, SharedPreferences, etc.).
 */
interface ProviderSettingsRepository {
    /**
     * Gets the enabled state for a provider with a custom default
     */
    fun isEnabled(forProvider: String, defaultValue: Boolean = true): Boolean

    /**
     * Sets the enabled state for a provider
     */
    fun setEnabled(enabled: Boolean, forProvider: String)
}
