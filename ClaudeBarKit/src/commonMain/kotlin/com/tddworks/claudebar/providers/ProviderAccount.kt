package com.tddworks.claudebar.providers

/**
 * A named login within a provider — a personal and a work one. Its lineup id is
 * `<providerId>.<accountId>`; the default login's is the provider's own id, as before logins
 * could be added.
 */
internal data class ProviderAccount(
    val accountId: String = DEFAULT_ACCOUNT_ID,
    val providerId: String,
    val label: String,
    val email: String? = null,
    val organization: String? = null,
) {
    /** `<providerId>.<accountId>`, or the provider's id for the default login. */
    val id: String get() = if (accountId == DEFAULT_ACCOUNT_ID) providerId else "$providerId.$accountId"

    /** Label first, then email, then the account id. */
    val displayName: String get() = label.ifEmpty { email ?: accountId }

    val isDefault: Boolean get() = accountId == DEFAULT_ACCOUNT_ID

    /** The display name's first letter, upper-cased, for avatar circles. */
    val initialLetter: String
        get() {
            val name = displayName
            if (name.isEmpty()) return ""
            val end = if (name[0].isHighSurrogate() && name.length > 1) 2 else 1
            return name.substring(0, end).uppercase()
        }

    companion object {
        const val DEFAULT_ACCOUNT_ID = "default"
    }
}
