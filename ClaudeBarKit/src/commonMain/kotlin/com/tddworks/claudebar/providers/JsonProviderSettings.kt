package com.tddworks.claudebar.providers

import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * Where earlier releases kept a few of a provider's settings and keys: UserDefaults. Read
 * once, and moved the first time the value is saved again.
 */
internal interface LegacyStore {
    fun string(key: String): String?

    /** Whether anything at all is kept under [key]. */
    fun contains(key: String): Boolean

    fun remove(key: String)
}

/**
 * Provider settings in `~/.claudebar/settings.json`, under exactly the keys the app has always
 * written (docs/settings.md): `providers.<id>.*` for the app's switches about a provider, and
 * `<id>.<setting>` for the provider's own settings and its data source (`<id>.probeMode`). A
 * value an old card kept elsewhere is read through the compatibility tables below.
 */
internal class JsonProviderSettings(
    private val file: SettingsFile,
    private val legacyStore: LegacyStore,
) : MultiAccountSettingsRepository {
    override fun isEnabled(provider: String, defaultValue: Boolean): Boolean = flag("providers.$provider.isEnabled") ?: defaultValue

    override fun setEnabled(enabled: Boolean, provider: String) = file.write("providers.$provider.isEnabled", JsonPrimitive(enabled))

    /** The key the old cards wrote (`<id>.probeMode`), so a mode picked before data sources still applies. */
    override fun dataSourceKind(provider: String): String? = file.string("$provider.probeMode")

    override fun setDataSourceKind(kind: String, provider: String) = file.write("$provider.probeMode", JsonPrimitive(kind))

    override fun cliPath(provider: String): String? = file.string("providers.$provider.cliPath")

    override fun setCLIPath(path: String?, provider: String) = file.write("providers.$provider.cliPath", path?.let(::JsonPrimitive))

    override fun isOn(setting: String, provider: String): Boolean? = flag("$provider.$setting")

    override fun setOn(on: Boolean, setting: String, provider: String) = file.write("$provider.$setting", JsonPrimitive(on))

    /** `<id>.<setting>`; a value an old card kept under another key is read from there, and moves the first time it is saved. */
    override fun value(setting: String, provider: String): String? {
        val key = "$provider.$setting"
        text(key)?.let { return it }
        legacySettingKeys[key]?.let { legacy -> text(legacy)?.let { return it } }
        return legacyDefaultsKeys[key]?.let(legacyStore::string)
    }

    override fun setValue(value: String?, setting: String, provider: String) {
        val key = "$provider.$setting"
        file.write(key, value?.let(::JsonPrimitive))
        legacySettingKeys[key]?.let { file.write(it, null) }
        legacyDefaultsKeys[key]?.let(legacyStore::remove)
    }

    override fun customCardURL(provider: String): String? = file.string("providers.$provider.customCardURL")

    override fun setCustomCardURL(url: String?, provider: String) =
        file.write("providers.$provider.customCardURL", url?.takeIf { it.isNotEmpty() }?.let(::JsonPrimitive))

    override fun providerOrder(): List<String> = strings("providers.order") ?: emptyList()

    /** An empty order removes the key, so the file keeps meaning "use the registration order". */
    override fun setProviderOrder(order: List<String>) = file.write("providers.order", order.takeIf { it.isNotEmpty() }?.let(::texts))

    override fun hiddenQuotaKeys(provider: String): Set<String> = strings("providers.$provider.hiddenQuotaKeys")?.toSet() ?: emptySet()

    /** Kept sorted; an empty set is a removal, so a fresh install reads back as "nothing hidden". */
    override fun setHiddenQuotaKeys(keys: Set<String>, provider: String) =
        file.write("providers.$provider.hiddenQuotaKeys", keys.takeIf { it.isNotEmpty() }?.let { texts(it.sorted()) })

    // Added logins

    override fun accounts(provider: String): List<ProviderAccountConfig> =
        (file.read(accountsKey(provider)) as? JsonArray)?.mapNotNull(::decodeAccount) ?: emptyList()

    override fun addAccount(config: ProviderAccountConfig, provider: String) {
        val configs = accounts(provider).toMutableList()
        val index = configs.indexOfFirst { it.accountId == config.accountId }
        if (index >= 0) configs[index] = config else configs += config
        writeAccounts(configs, provider)
    }

    override fun removeAccount(accountId: String, provider: String) =
        writeAccounts(accounts(provider).filter { it.accountId != accountId }, provider)

    override fun updateAccount(config: ProviderAccountConfig, provider: String) {
        val configs = accounts(provider).toMutableList()
        val index = configs.indexOfFirst { it.accountId == config.accountId }
        if (index < 0) return
        configs[index] = config
        writeAccounts(configs, provider)
    }

    override fun defaultAccountLabel(provider: String): String? = file.string("providers.$provider.defaultAccountLabel")

    override fun setDefaultAccountLabel(label: String?, provider: String) =
        file.write("providers.$provider.defaultAccountLabel", label?.let(::JsonPrimitive))

    override fun accountOrder(provider: String): List<String> = strings("providers.$provider.accountOrder") ?: emptyList()

    override fun setAccountOrder(accountIds: List<String>, provider: String) =
        file.write("providers.$provider.accountOrder", accountIds.takeIf { it.isNotEmpty() }?.let(::texts))

    private fun accountsKey(provider: String) = "providers.$provider.accounts"

    /** An empty list is a removal, so the file stays free of empty arrays. */
    private fun writeAccounts(configs: List<ProviderAccountConfig>, provider: String) =
        file.write(accountsKey(provider), configs.takeIf { it.isNotEmpty() }?.let { list -> JsonArray(list.map(::encodeAccount)) })

    // Reading values as the old cards wrote them

    /** A flag; a stored 0 or 1 reads as one too, as Foundation bridges it. */
    private fun flag(key: String): Boolean? {
        val value = file.read(key) as? JsonPrimitive ?: return null
        if (value.isString) return null
        value.booleanOrNull?.let { return it }
        return when (value.content.toDoubleOrNull()) {
            0.0 -> false
            1.0 -> true
            else -> null
        }
    }

    /** A list of text; null when it isn't one. */
    private fun strings(key: String): List<String>? = (file.read(key) as? JsonArray)?.let { list ->
        list.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: return null }
    }

    /** A value as text — an old card may have saved a number, or a list (read as `a, b`). */
    private fun text(key: String): String? = when (val value = file.read(key)) {
        is JsonPrimitive -> when {
            value.isString -> value.content
            value.booleanOrNull != null -> null
            else -> numberText(value.content)
        }
        is JsonArray -> strings(key)?.joinToString(", ")
        else -> null
    }

    private fun texts(values: List<String>): JsonElement = JsonArray(values.map(::JsonPrimitive))

    private companion object {
        /** Settings a provider's card kept under a key that isn't `<id>.<setting>`. A migrating provider adds a row here, never a branch. */
        val legacySettingKeys = mapOf(
            "vercel-gateway.authEnvVar" to "vercel.authEnvVar",
        )

        /** Settings a provider's card kept in UserDefaults; they move to settings.json the first time they are saved. */
        val legacyDefaultsKeys = mapOf(
            "copilot.username" to "com.claudebar.credentials.github-username",
        )

        // The keys Swift's synthesized Codable wrote: optionals left out when absent.
        fun encodeAccount(config: ProviderAccountConfig): JsonElement = JsonObject(buildMap {
            put("accountId", JsonPrimitive(config.accountId))
            put("label", JsonPrimitive(config.label))
            config.email?.let { put("email", JsonPrimitive(it)) }
            config.organization?.let { put("organization", JsonPrimitive(it)) }
            put("probeConfig", JsonObject(config.probeConfig.mapValues { JsonPrimitive(it.value) }))
            config.madeBy?.let { put("madeBy", JsonPrimitive(it.tag)) }
        })

        /** A login as saved, or null when it isn't one — a broken entry is skipped, never the whole list. */
        fun decodeAccount(json: JsonElement): ProviderAccountConfig? {
            val o = json as? JsonObject ?: return null
            fun text(key: String): String? = (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
            fun optional(key: String): Result<String?> = when (val value = o.present(key)) {
                null -> Result.success(null)
                else -> (value as? JsonPrimitive)?.takeIf { it.isString }?.let { Result.success(it.content) }
                    ?: Result.failure(IllegalArgumentException(key))
            }
            val probeConfig = (o["probeConfig"] as? JsonObject)?.mapValues { (_, value) ->
                (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            } ?: return null
            val madeBy = when (val tag = optional("madeBy").getOrElse { return null }) {
                null -> null
                else -> AccountOrigin.entries.firstOrNull { it.tag == tag } ?: return null
            }
            return ProviderAccountConfig(
                accountId = text("accountId") ?: return null,
                label = text("label") ?: return null,
                email = optional("email").getOrElse { return null },
                organization = optional("organization").getOrElse { return null },
                probeConfig = probeConfig,
                madeBy = madeBy,
            )
        }
    }
}
