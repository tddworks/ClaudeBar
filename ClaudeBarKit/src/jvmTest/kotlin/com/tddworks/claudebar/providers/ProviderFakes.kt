package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Paths
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.datasources.SignInProcess
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertTrue
import java.io.File
import java.util.Collections

// Hand-written stand-ins for what a Provider reads and writes: the real behaviour it relies
// on, kept in memory.

/** A settings repository in memory — what a `Provider` relies on, without `~/.claudebar/settings.json`. */
internal class InMemoryProviderSettings(
    dataSourceKinds: Map<String, String> = emptyMap(),
    flags: Map<String, Boolean> = emptyMap(),
) : MultiAccountSettingsRepository {
    private val configs = mutableMapOf<String, MutableList<ProviderAccountConfig>>()
    private val defaultLabels = mutableMapOf<String, String>()
    private val enabled = mutableMapOf<String, Boolean>()
    private val kinds = dataSourceKinds.toMutableMap()
    private val cardURLs = mutableMapOf<String, String>()

    /** `<provider>.<setting>` → on or off, as settings.json keeps them. */
    private val flags = flags.toMutableMap()
    private val values = mutableMapOf<String, String>()
    private val cliPaths = mutableMapOf<String, String>()
    private val hidden = mutableMapOf<String, Set<String>>()
    private val orders = mutableMapOf<String, List<String>>()
    private var order = emptyList<String>()

    override fun isEnabled(provider: String, defaultValue: Boolean) = enabled[provider] ?: defaultValue
    override fun setEnabled(enabled: Boolean, provider: String) { this.enabled[provider] = enabled }
    override fun customCardURL(provider: String) = cardURLs[provider]
    override fun setCustomCardURL(url: String?, provider: String) { if (url == null) cardURLs.remove(provider) else cardURLs[provider] = url }
    override fun dataSourceKind(provider: String) = kinds[provider]
    override fun setDataSourceKind(kind: String, provider: String) { kinds[provider] = kind }
    override fun isOn(setting: String, provider: String) = flags["$provider.$setting"]
    override fun setOn(on: Boolean, setting: String, provider: String) { flags["$provider.$setting"] = on }
    override fun providerOrder() = order
    override fun setProviderOrder(order: List<String>) { this.order = order }
    override fun value(setting: String, provider: String) = values["$provider.$setting"]
    override fun setValue(value: String?, setting: String, provider: String) {
        if (value == null) values.remove("$provider.$setting") else values["$provider.$setting"] = value
    }
    override fun cliPath(provider: String) = cliPaths[provider]
    override fun setCLIPath(path: String?, provider: String) { if (path == null) cliPaths.remove(provider) else cliPaths[provider] = path }
    override fun hiddenQuotaKeys(provider: String) = hidden[provider] ?: emptySet()
    override fun setHiddenQuotaKeys(keys: Set<String>, provider: String) { hidden[provider] = keys }

    override fun accounts(provider: String): List<ProviderAccountConfig> = configs[provider]?.toList() ?: emptyList()
    override fun addAccount(config: ProviderAccountConfig, provider: String) {
        val list = configs.getOrPut(provider) { mutableListOf() }
        list.removeAll { it.accountId == config.accountId }
        list += config
    }
    override fun removeAccount(accountId: String, provider: String) { configs[provider]?.removeAll { it.accountId == accountId } }
    override fun updateAccount(config: ProviderAccountConfig, provider: String) {
        val list = configs[provider] ?: return
        val index = list.indexOfFirst { it.accountId == config.accountId }
        if (index >= 0) list[index] = config
    }
    override fun defaultAccountLabel(provider: String) = defaultLabels[provider]
    override fun setDefaultAccountLabel(label: String?, provider: String) {
        if (label == null) defaultLabels.remove(provider) else defaultLabels[provider] = label
    }
    override fun accountOrder(provider: String) = orders[provider] ?: emptyList()
    override fun setAccountOrder(accountIds: List<String>, provider: String) { orders[provider] = accountIds }
}

/** A vault in memory, keyed `<provider>.<name>`. */
internal class MemoryVault(secrets: Map<String, String> = emptyMap()) : SecretVault {
    val secrets: MutableMap<String, String> = Collections.synchronizedMap(secrets.toMutableMap())
    override fun secret(name: String, provider: String): String? = secrets["$provider.$name"]
    override fun save(value: String, name: String, provider: String) { secrets["$provider.$name"] = value }
    override fun delete(name: String, provider: String): Boolean = secrets.remove("$provider.$name") != null
}

/** A vault that seems to save and keeps nothing — an ad-hoc build's Keychain. */
internal class RefusingVault : SecretVault {
    override fun secret(name: String, provider: String): String? = null
    override fun save(value: String, name: String, provider: String) {}
    override fun delete(name: String, provider: String): Boolean = false
}

/** The *In use* records in memory: what the shell would read after switching, without `~/.claudebar`. */
internal class InMemoryLoginsInUse(existing: Map<String, String> = emptyMap()) : LoginsInUse {
    private val folders = Collections.synchronizedMap(existing.toMutableMap())
    override fun folder(command: String): String? = folders[command]
    override fun use(folder: String?, command: String) {
        if (folder == null) folders.remove(command) else folders[command] = SignedInFolder(folder, AccountOrigin.FOLDER).path
    }
}

/** This JVM's view of the disk as a path setting asks it: `~` is [home], symlinks resolved. */
internal class HomePaths(private val home: String, private val environment: (String) -> String? = { null }) : PathChecking {
    override fun expanded(path: String): String = Paths.expand(path, home, environment)
    override fun isFolder(path: String): Boolean = File(canonical(path)).isDirectory
    override fun canonical(path: String): String = File(expanded(path)).canonicalPath
}

/** A CLI's own sign-in that does [run] in the folder it is given, and answers [status]. */
internal class ScriptedSignIn(private val status: Int = 0, private val run: (executable: String, folder: String) -> Unit = { _, _ -> }) : SignInProcess {
    /** Where each sign-in ran, and with which executable. */
    val launches: MutableList<Pair<String, String>> = Collections.synchronizedList(mutableListOf())

    override suspend fun run(executable: String, arguments: List<String>, environment: Map<String, String>, directory: String, timeoutSeconds: Double): Int {
        launches += executable to directory
        run(executable, directory)
        return status
    }
}

// Tests ask a product about its plain login, as the app asks it about any login: a login never refers to its provider.

internal fun Provider.refreshPlain(kind: RefreshKind = RefreshKind.INTERACTIVE): RefreshOutcome = runBlocking { refresh(defaultAccount, kind) }

internal fun Provider.refreshNow(account: Account, kind: RefreshKind = RefreshKind.INTERACTIVE): RefreshOutcome = runBlocking { refresh(account, kind) }

internal fun Provider.isPlainAvailable(): Boolean = runBlocking { isAvailable(defaultAccount) }

internal val Provider.plainDashboardURL: String? get() = dashboardURL(defaultAccount)

internal val Provider.plainIsInLineup: Boolean get() = isInLineup(defaultAccount)

/** The usage a refresh showed; fails the test when it failed. */
internal fun RefreshOutcome.usage(): UsageSnapshot {
    assertTrue(this is RefreshOutcome.Refreshed, "expected usage, got $this")
    return (this as RefreshOutcome.Refreshed).usage
}

/** What a command came to, when it was done; fails the test when it was refused. */
internal fun <T> Outcome<T>.done(): T {
    assertTrue(this is Outcome.Done, "expected it done, got $this")
    return (this as Outcome.Done).value
}
