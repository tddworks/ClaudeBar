package com.tddworks.claudebar.domain.provider

/**
 * Interface for storing and retrieving credentials.
 * Allows different implementations (UserDefaults, Keychain, etc.) and easy testing.
 */
interface CredentialRepository {
    /**
     * Saves a credential value for the given key.
     */
    fun save(value: String, forKey: String)

    /**
     * Retrieves a credential value for the given key.
     */
    fun get(forKey: String): String?

    /**
     * Deletes the credential for the given key.
     */
    fun delete(forKey: String)

    /**
     * Checks if a credential exists for the given key.
     */
    fun exists(forKey: String): Boolean
}

/**
 * Well-known credential keys
 */
object CredentialKey {
    const val GITHUB_TOKEN = "github-copilot-token"
    const val GITHUB_USERNAME = "github-username"
}
