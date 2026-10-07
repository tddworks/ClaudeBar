package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.flow.StateFlow

/**
 * *The provider's Settings page* — its DATA SOURCE (which one, its fallback), its settings
 * form's values and its CLI location (TARGET §2.1).
 *
 * It owns what it decides and knows no one above it: not the provider, not a login. It answers
 * what a login runs ([sources]), and every change that alters that grows [sourcesRevision] —
 * the provider pulls, and remakes a login's data sources when they are older.
 */
public class Configuration internal constructor(
    private val definition: ProviderDefinition,
    private val settings: ProviderSettingsRepository,
    internal val vault: SecretVault?,
    internal val paths: PathChecking,
    private val isExecutable: (String) -> Boolean,
    private val locate: (String) -> String?,
) {
    private data class Choice(
        val sourcesRevision: Int,
        /** *CLI location* — where this provider's CLI lives on this Mac, when the person chose one (#210). */
        val cliPath: String?,
        /** The definition as it runs here: the CLI at the person's location. */
        val running: ProviderDefinition,
    )

    private val state: ObservableState<Choice>

    init {
        val cliPath = settings.cliPath(definition.id)
        val running = try {
            definition.runningCLI(cliPath ?: installedCLI() ?: "")
        } catch (error: Exception) {
            AppLog.providers.error("${definition.id}: can't run the CLI at the saved location: ${error.message}")
            definition
        }
        state = ObservableState(Choice(0, cliPath, running))
    }

    private val id: String get() = definition.id
    private val name: String get() = definition.profile.name

    /** Bumped after every change on the page — a choice, a value, a location. */
    val revision: StateFlow<Long> get() = state.revision

    /** Grows on every change a login's data sources are made from. */
    internal val sourcesRevision: Int get() = state.current.sourcesRevision

    /** *CLI location* — null finds the CLI as usual. */
    val cliPath: String? get() = state.current.cliPath

    internal val running: ProviderDefinition get() = state.current.running

    // DATA SOURCE — one choice for every login

    /** The data source in use: the one the person picked, else the default. */
    val activeKind: String
        get() {
            val chosen = settings.dataSourceKind(id)
            if (chosen != null && definition.dataSource(chosen) != null) return chosen
            return definition.defaultDataSource
        }

    /** Switches the data source. False when the provider has no such one. */
    fun use(kind: String): Boolean {
        if (definition.dataSource(kind) == null) return false
        settings.setDataSourceKind(kind, id)
        state.update { it }
        return true
    }

    /**
     * Whether a data source's fallback is on — one the definition lets the person turn off
     * (`enabledBySetting`) reads that setting; any other is always on. False when there is none.
     */
    fun isFallbackEnabled(kind: String): Boolean {
        val fallback = definition.dataSource(kind)?.fallback ?: return false
        val setting = fallback.enabledBySetting ?: return true
        return settings.isOn(setting, id) != false
    }

    /** Turns a switchable fallback on or off; does nothing for one that isn't. */
    fun setFallbackEnabled(on: Boolean, kind: String) {
        val setting = definition.dataSource(kind)?.fallback?.enabledBySetting ?: return
        settings.setOn(on, setting, id)
        state.update { it }
    }

    /** What to do when the active data source's key lookup finds no key — the lookup's own hint. */
    val keyHint: String? get() = definition.dataSource(activeKind)?.credential?.hint

    // The settings form — REGION, API KEY, ENV VAR …

    /**
     * What a setting holds for a login with these own values (the plain login has none): its
     * own value for an account-scope one, else the provider's saved value, else its default.
     * Never a secret's.
     */
    fun value(setting: Setting, ownValues: Map<String, String>): String? =
        setting.value(setting.ownValue(ownValues) ?: settings.value(setting.id, id)).ifEmpty { null }

    /** What a setting holds for this login. */
    fun value(setting: Setting, account: Account): String? = value(setting, if (account.isDefault) emptyMap() else account.values)

    /**
     * Whether a value of this setting is saved for a login — a key in the vault under its id,
     * or a value of its own (null own values: the plain login, whose values are the
     * provider's) — never the value itself.
     */
    fun hasSaved(setting: Setting, login: String, ownValues: Map<String, String>?): Boolean {
        if (vault?.secret(setting.id, login) != null) return true
        val own = if (ownValues != null) ownValues[setting.id] else settings.value(setting.id, id)
        return own != null
    }

    /** Whether a value of this setting is saved for this login. */
    fun hasSaved(setting: Setting, account: Account): Boolean =
        hasSaved(setting, account.id, if (account.isDefault) null else account.values)

    /**
     * Fills in a provider-scope setting — or the plain login's value of an account-scope one —
     * for every login from the next refresh. A secret goes to the vault; null or empty forgets it.
     */
    fun set(setting: String, value: String?): Outcome<Unit> = outcome {
        val found = definition.setting(setting) ?: throw UsageError.ExecutionFailed("$name has no setting $setting.")
        val kept = value?.trim()?.ifEmpty { null }
        if (kept != null) found.check(kept, paths)?.let { throw UsageError.ExecutionFailed(it) }
        val entry = SettingEntry()
        if (kept != null) found.keep(kept, entry, paths)
        if (entry.secrets.isNotEmpty() && vault == null) throw UsageError.ExecutionFailed("ClaudeBar can't keep this key securely here.")
        settings.setValue(entry.values[setting], setting, id)
        if (entry.secrets.isEmpty()) vault?.delete(setting, id) else keep(entry.secrets, id)
        state.update { it.copy(sourcesRevision = it.sourcesRevision + 1) }
    }

    /**
     * Saves keys in the vault under a login, reading each back: an ad-hoc build's Keychain can
     * seem to save and keep nothing. On a refusal every key goes back to what it was — a key
     * being replaced is never lost.
     */
    internal fun keep(secrets: Map<String, String>, login: String) {
        val before = secrets.keys.associateWith { vault?.secret(it, login) }
        for ((name, value) in secrets) {
            vault?.save(value, name, login)
            if (vault?.secret(name, login) != value) {
                for ((key, previous) in before) {
                    vault?.delete(key, login)
                    if (previous != null) vault?.save(previous, key, login)
                }
                throw UsageError.ExecutionFailed("ClaudeBar couldn't keep this key securely.")
            }
        }
    }

    // CLI location

    /**
     * Where the CLI is when the person chose no location: on the PATH, or else the first other
     * place in `cli` that is a program. The PATH is asked only when such a place exists.
     */
    private fun installedCLI(): String? {
        val name = definition.cli ?: return null
        val place = definition.cliPlaces.map(paths::expanded).firstOrNull(isExecutable) ?: return null
        return if (locate(name) == null) place else null
    }

    /**
     * Runs this provider's CLI from [path] for every login and for Add Account's sign-in, saved
     * and in effect at once. Empty goes back to finding the CLI as usual. A path that isn't a
     * program is refused, and nothing changes.
     */
    fun setCLIPath(path: String?): Outcome<Unit> = outcome {
        val trimmed = (path ?: "").trim()
        val chosen = when {
            trimmed.isEmpty() -> null
            trimmed.startsWith("~") -> paths.expanded(trimmed)
            else -> trimmed
        }
        if (chosen != null && !isExecutable(chosen)) {
            throw UsageError.ExecutionFailed("$chosen isn't a program ClaudeBar can run. Choose the ${definition.cli ?: name} executable itself.")
        }
        val running = definition.runningCLI(chosen ?: installedCLI() ?: "")
        state.update { it.copy(sourcesRevision = it.sourcesRevision + 1, cliPath = chosen, running = running) }
        settings.setCLIPath(chosen, id)
    }

    // What a login runs

    /**
     * The definition as the plain login runs it — the CLI at its chosen location and every
     * `{{setting.x}}` filled — so Settings prints `$MINIMAX_API_KEY`, not the template.
     */
    val definitionAsRun: ProviderDefinition
        get() {
            val running = running
            val sources = runCatching { sources(emptyMap(), isDefault = true) }.getOrNull() ?: running.dataSources
            return ProviderDefinition(
                profile = running.profile, cli = running.cli, enabledByDefault = running.enabledByDefault,
                dataSources = sources, defaultDataSource = running.defaultDataSource, together = running.together,
                accounts = running.accounts, settings = running.settings, usageHistory = running.usageHistory, setup = running.setup,
            )
        }

    /** A login's data sources as data: an added one's patched and filled with its values, then every login's settings filled in. */
    internal fun sources(values: Map<String, String>, isDefault: Boolean): List<DataSourceDefinition> {
        val running = running
        val sources = if (isDefault) running.dataSources else running.dataSourcesForAccount(values)
        val fills = settingFills(if (isDefault) emptyMap() else values)
        if (fills.isEmpty()) return sources
        return sources.map { it.filled(fills, "setting") }
    }

    /** Every `{{setting.x}}` a login's data sources are filled with. */
    fun settingFills(ownValues: Map<String, String>): Map<String, String> =
        definition.settings.fold(emptyMap()) { fills, setting -> fills + setting.fills(value(setting, ownValues)) }
}
