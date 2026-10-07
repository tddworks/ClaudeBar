package com.tddworks.claudebar.providers

/**
 * A provider's settings — on or off, its data source, its own settings by name, the lineup
 * order, hidden quotas. The app keeps them in `~/.claudebar/settings.json` ([JsonProviderSettings]).
 * A conformer that keeps no such setting answers with the definition's default.
 */
internal interface ProviderSettingsRepository {
    /** Whether the provider is on; [defaultValue] until the person chooses. */
    fun isEnabled(provider: String, defaultValue: Boolean = true): Boolean

    fun setEnabled(enabled: Boolean, provider: String)

    /** The page a card opens instead of the dashboard; null when not set. */
    fun customCardURL(provider: String): String?

    /** Saves it; empty or null removes it. */
    fun setCustomCardURL(url: String?, provider: String)

    /** The `kind` of the data source a provider uses — what Settings calls PROBE MODE. Null until the person picks one. */
    fun dataSourceKind(provider: String): String? = null

    fun setDataSourceKind(kind: String, provider: String) {}

    /** A provider's on/off setting by name — `isOn("cliFallbackEnabled", "<id>")`. Null when never set. */
    fun isOn(setting: String, provider: String): Boolean? = null

    fun setOn(on: Boolean, setting: String, provider: String) {}

    /**
     * The person's provider display order, empty when never reordered. Ids missing from it keep
     * their place; ids of providers that no longer exist are ignored.
     */
    fun providerOrder(): List<String> = emptyList()

    /** An empty order clears it. */
    fun setProviderOrder(order: List<String>) {}

    /** A provider-scope setting's value by name, kept as `<id>.<setting>`. Null when never set. Never a secret: those live in the vault. */
    fun value(setting: String, provider: String): String? = null

    /** Saves it; null forgets it, so the setting's default applies. */
    fun setValue(value: String?, setting: String, provider: String) {}

    /** Where the provider's CLI lives on this Mac, when the person chose one — *CLI location* (#210). */
    fun cliPath(provider: String): String? = null

    fun setCLIPath(path: String?, provider: String) {}

    /** The quota keys hidden for a provider (#140); empty shows all. Keys no longer reported are ignored when read. */
    fun hiddenQuotaKeys(provider: String): Set<String> = emptySet()

    fun setHiddenQuotaKeys(keys: Set<String>, provider: String) {}
}

/** A provider's settings, plus the logins added beside its default one. */
internal interface MultiAccountSettingsRepository : ProviderSettingsRepository {
    /** The added logins, in the order they were added; empty for a provider with only its default login. */
    fun accounts(provider: String): List<ProviderAccountConfig>

    /** Adds a login, or replaces the one with its account id. */
    fun addAccount(config: ProviderAccountConfig, provider: String)

    fun removeAccount(accountId: String, provider: String)

    /** Changes a login in place; nothing when there is no such login. */
    fun updateAccount(config: ProviderAccountConfig, provider: String)

    /** The name the person gave the default login — added logins keep theirs in [ProviderAccountConfig.label]. */
    fun defaultAccountLabel(provider: String): String?

    fun setDefaultAccountLabel(label: String?, provider: String)

    /** The order the person put the logins in, by account id (`default` for the default login). Empty until they move one. */
    fun accountOrder(provider: String): List<String>

    fun setAccountOrder(accountIds: List<String>, provider: String)
}

/** One added login, as settings.json keeps it. */
internal data class ProviderAccountConfig(
    val accountId: String,
    val label: String,
    val email: String? = null,
    val organization: String? = null,
    /** The login's own values — its folder, its account id — by name. */
    val probeConfig: Map<String, String> = emptyMap(),
    /** How the login was added — which decides what *Remove* may delete. Null for logins saved before it was recorded: treated as chosen. */
    val madeBy: AccountOrigin? = null,
) {
    /** The same login under another name — who it is and its values stay. */
    fun named(label: String): ProviderAccountConfig = copy(label = label)

    /** The same login, recorded as added that way. */
    fun made(origin: AccountOrigin): ProviderAccountConfig = copy(madeBy = origin)

    fun toProviderAccount(providerId: String) = ProviderAccount(accountId, providerId, label, email, organization)
}

/** How a login was added: *Choose Signed-in Folder*, *Sign in with browser* (into a folder ClaudeBar made), or the account's form. */
internal enum class AccountOrigin(val tag: String) {
    FOLDER("folder"),
    SIGN_IN("signIn"),
    FORM("form"),
}
