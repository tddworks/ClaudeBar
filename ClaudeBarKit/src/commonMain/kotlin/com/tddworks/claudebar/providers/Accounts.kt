package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSource
import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.LoginFolders
import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.datasources.process.AccountSignIn
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.flow.StateFlow
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * *The Accounts card* — a provider's logins, in the order the person put them, and what you
 * tell them: add one (by its form, a signed-in folder or signing in), remove, rename, move,
 * sign in again (TARGET §2.1).
 *
 * It owns the logins and knows no one above it. What its provider must follow — a login kept
 * or let go — it reports through `onChange`, the one callback the provider gives it: an event
 * going out, never a reference up. Read as a list, it is the logins in the person's order.
 */
public class Accounts internal constructor(
    private val definition: ProviderDefinition,
    private val settings: MultiAccountSettingsRepository,
    private val configuration: Configuration,
    private val folders: LoginFolders,
    private val makeDataSource: (DataSourceDefinition, String) -> DataSource,
    private val makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)?,
    /** *Sign in with browser*'s runner, when this Mac can run one. */
    private val signInRunner: AccountSignIn?,
    /** Where *Sign in with browser* makes its folders — `~/.claudebar/accounts`. */
    private val signInRoot: String,
) {
    /** What happened to the logins, for the provider to follow. */
    sealed class Change {
        /** A login was kept; [byKey] when the person supplied its key — an opt-in to the product too. */
        data class Added(val account: Account, val byKey: Boolean) : Change()

        data class Removed(val account: Account) : Change()
    }

    /** The logins, in the person's order — never empty once started, one the default. */
    private val state = ObservableState(emptyList<Account>())

    /** Where what happened goes — given once by the provider. */
    private var onChange: (Change) -> Unit = {}

    /** Bumped after a login is added, removed or moved. */
    val revision: StateFlow<Long> get() = state.revision

    private val logins: List<Account> get() = state.current

    /** The logins, in the person's order. */
    val all: List<Account> get() = logins

    val size: Int get() = logins.size

    operator fun get(index: Int): Account = logins[index]

    /**
     * The logins saved for this provider, made — the plain login first (with the history and
     * guest passes only it has), then each saved one, in the saved order.
     */
    internal fun start(plainHistory: UsageHistory?, guestPasses: GuestPasses?, onChange: (Change) -> Unit, saved: List<ProviderAccountConfig>) {
        val label = settings.defaultAccountLabel(id) ?: ""
        val plain = Account(definition, settings, ProviderAccount(providerId = id, label = label), emptyMap(),
            usageHistory = plainHistory, guestPasses = guestPasses)
        state.update { listOf(plain) }
        for (config in saved) attach(config)
        val order = settings.accountOrder(id)
        state.update { made ->
            made.withIndex().sortedBy { (offset, login) ->
                order.indexOf(login.accountId).takeIf { it >= 0 } ?: (order.size + offset)
            }.map { it.value }
        }
        this.onChange = onChange
    }

    private val id: String get() = definition.id
    private val name: String get() = definition.profile.name

    // It answers

    /** The plain login the CLI already uses — found by being the default, wherever the person moved it. */
    val plain: Account get() = logins.first { it.isDefault }

    /** The login a person or a link names: its id, its account id (`default` for the plain login), its name or its email — any case. */
    fun named(name: String): Account? {
        val wanted = name.lowercase()
        val logins = logins
        return logins.firstOrNull { it.id.lowercase() == wanted || it.accountId.lowercase() == wanted }
            ?: logins.firstOrNull { it.displayName.lowercase() == wanted || it.accountEmail?.lowercase() == wanted }
    }

    /** More than one enabled login, so each needs telling apart by name. */
    val hasSeveral: Boolean get() = logins.count { it.isEnabled } > 1

    /** The enabled login with the most left — *switch to work*. */
    val best: Account?
        get() = logins.filter { it.isEnabled }
            .maxByOrNull { it.snapshot?.lowestQuota?.percentRemaining ?: Double.NEGATIVE_INFINITY }

    /** The enabled login that makes the provider's status what it is — the one the popover names. Null while every login is healthy. */
    val worst: Account?
        get() {
            val worst = logins.filter { it.isEnabled }.maxByOrNull { it.status } ?: return null
            return worst.takeIf { it.status > QuotaStatus.HEALTHY }
        }

    /** What *Add Account*'s form asks for: the account settings the active data source uses. */
    val form: List<Setting> get() = definition.accountSettings.filter { it.isUsed(configuration.activeKind) }

    // Tell it

    /**
     * A saved login kept beside the default one — what each way of adding ends in. Null when
     * the definition has no added accounts, the login is already listed, or its values don't
     * fill what the definition needs.
     */
    internal fun add(config: ProviderAccountConfig, byKey: Boolean = false): Account? {
        val account = attach(config) ?: return null
        settings.addAccount(config, id)
        onChange(Change.Added(account, byKey))
        return account
    }

    /**
     * *Choose Signed-in Folder* — adds the login a folder holds, read by the definition's own
     * lookups filled with that folder. Refused when the folder holds no key, or the login is
     * the default one or already listed.
     */
    fun add(signedInAt: String): Outcome<Account> = outcome { add(SignedInFolder(signedInAt, AccountOrigin.FOLDER)) }

    /**
     * *Add Account* by its form — the login's own account-scope settings. Each value keeps its
     * setting's rule, a default fills a blank, a path is never another login's, and a secret is
     * kept in the vault under the new login's id — read back before the login is kept, so
     * nothing is half saved. Supplying a key opts the login, and its product, in.
     */
    @OptIn(ExperimentalUuidApi::class)
    fun add(filling: Map<String, String>): Outcome<Account> = outcome {
        val form = form
        if (form.isEmpty()) throw UsageError.ExecutionFailed("$name has no account form.")
        val entry = SettingEntry()
        for (setting in form) {
            val value = setting.value(filling[setting.id])
            setting.check(value, configuration.paths)?.let { throw UsageError.ExecutionFailed(it) }
            if (isTaken(value, setting)) {
                throw UsageError.ExecutionFailed("Choose a separate folder for ${setting.label} — another $name login uses this one.")
            }
            setting.keep(value, entry, configuration.paths)
        }
        val vault = configuration.vault
        if (entry.secrets.isNotEmpty() && vault == null) throw UsageError.ExecutionFailed("ClaudeBar can't keep this key securely here.")
        val config = ProviderAccountConfig(Uuid.random().toString().lowercase(), "", probeConfig = entry.values.toMap(), madeBy = AccountOrigin.FORM)
        val lineupId = config.toProviderAccount(id).id
        try {
            configuration.keep(entry.secrets, lineupId)
        } catch (refused: UsageError) {
            throw UsageError.ExecutionFailed("ClaudeBar couldn't keep this key securely. The account wasn't added.")
        }
        val account = add(config, byKey = true)
        if (account == null) {
            for (secret in entry.secrets.keys) vault?.delete(secret, lineupId)
            throw UsageError.ExecutionFailed("This $name account can't be added.")
        }
        account.isEnabled = true
        account
    }

    /**
     * *Sign in with browser* — runs the definition's login into a new folder under [root], then
     * adds it as *Choose Signed-in Folder* would. A folder that ends up holding no new login is deleted.
     */
    suspend fun signIn(): Outcome<Account> = signIn(signInRunner, signInRoot)

    internal suspend fun signIn(runner: AccountSignIn?, root: String = signInRoot): Outcome<Account> = outcome {
        val call = configuration.running.accounts?.signIn
        if (call == null || runner == null) throw UsageError.ExecutionFailed("$name has no sign-in.")
        val folder = SignedInFolder.forSignIn(id, root)
        runner.signIn(call, folder.path)
        try {
            add(folder)
        } catch (refused: Exception) {
            folders.delete(folder.path)
            throw refused
        }
    }

    /**
     * *Re-auth* for a login ClaudeBar signed in to: runs the definition's login again in that
     * login's own folder. Refresh it after, so the identity rule decides whether the same person
     * came back. A folder the person chose is theirs to sign in to; ClaudeBar never runs a login there.
     */
    suspend fun signInAgain(account: Account): Outcome<Unit> = signInAgain(account, signInRunner)

    internal suspend fun signInAgain(account: Account, runner: AccountSignIn?): Outcome<Unit> = outcome {
        val call = configuration.running.accounts?.signIn
        val folder = account.folder
        if (call == null || runner == null || folder == null || !folder.goesWithAccount) {
            throw UsageError.ExecutionFailed("Sign in again in this folder yourself, then refresh.")
        }
        runner.signInAgain(call, folder.path)
    }

    /**
     * *Remove* — forgets the login here and its saved settings, and deletes the folder only
     * when ClaudeBar made it by signing in. A folder the person chose is theirs and stays. The
     * default login can't be removed.
     */
    fun remove(account: Account) {
        if (account.isDefault || logins.none { it === account }) return
        account.folder?.takeIf { it.goesWithAccount }?.let { folders.delete(it.path) }
        // Whatever of the form went to the vault goes with the login.
        for (setting in definition.accountSettings) configuration.vault?.delete(setting.id, account.id)
        state.update { logins -> logins.filterNot { it === account } }
        account.usageHistory = null
        settings.removeAccount(account.accountId, id)
        onChange(Change.Removed(account))
    }

    /** *Rename* — the name the person gives a login. Who it is, its values and its usage stay; an empty name goes back to the email. */
    fun rename(account: Account, name: String) {
        if (logins.none { it === account }) return
        val label = name.trim()
        if (account.isDefault) {
            settings.setDefaultAccountLabel(label.ifEmpty { null }, id)
        } else {
            settings.accounts(id).firstOrNull { it.accountId == account.accountId }?.let { settings.updateAccount(it.named(label), id) }
        }
        account.label = label
    }

    /** *Move* — puts a login at [index] in the person's order, saved. */
    fun move(account: Account, index: Int) {
        if (logins.none { it === account }) return
        val moved = state.update { logins ->
            val rest = logins.filterNot { it === account }.toMutableList()
            rest.add(index.coerceIn(0, rest.size), account)
            rest
        }
        settings.setAccountOrder(moved.map { it.accountId }, id)
    }

    // Private

    /** A saved login made — its values checked against what the definition needs, its own usage history handed to it. */
    private fun attach(config: ProviderAccountConfig): Account? {
        val login = config.toProviderAccount(id)
        if (definition.accounts == null || login.isDefault || logins.any { it.id == login.id }) return null
        val values = config.probeConfig.toMutableMap()
        val paths = configuration.paths
        definition.accounts.folder?.savedAs?.let { field ->
            values[field]?.takeIf { it.isNotEmpty() }?.let { values[field] = paths.canonical(it) }
        }
        for (setting in definition.accountSettings) {
            if (setting.kind !is Setting.Kind.Path) continue
            values[setting.id]?.takeIf { it.isNotEmpty() }?.let { values[setting.id] = paths.canonical(it) }
        }
        try {
            configuration.sources(values, isDefault = false)
        } catch (error: Exception) {
            AppLog.providers.error("$id: can't run account ${login.id}: ${error.message}")
            return null
        }
        val history = definition.usageHistoryForAccount(values)?.let { own -> makeUsageHistory?.invoke(own, login.id) }
        val account = Account(definition, settings, login, values.toMap(), config.madeBy, history)
        state.update { it + account }
        return account
    }

    /** Two logins never share a path setting — the default login's included. */
    private fun isTaken(value: String, setting: Setting): Boolean = logins.any { account ->
        val other = configuration.value(setting, if (account.isDefault) emptyMap() else account.values) ?: return@any false
        setting.isSamePlace(value, other, configuration.paths)
    }

    @OptIn(ExperimentalUuidApi::class)
    private fun add(folder: SignedInFolder): Account {
        val rule = definition.accounts?.folder ?: throw UsageError.ExecutionFailed("$name has no added accounts.")
        val paths = configuration.paths
        val home = paths.canonical(folder.path)
        val defaultHome = rule.default?.let(paths::canonical)
        if (home == defaultHome) throw UsageError.ExecutionFailed("This is the default $name login, which is already listed.")
        val values = rule.values(home)
        val login = signedIn(values + (rule.accountId.savedAs to ""), rule)
        val accountId = login?.first
        val email = login?.second
        if (accountId == null || email == null) throw UsageError.ExecutionFailed(rule.notSignedIn ?: "No $name login found in this folder.")
        val listed = logins.any { account ->
            account.values[rule.accountId.savedAs] == accountId || account.folder?.let { paths.canonical(it.path) } == home
        }
        if (accountId == plainAccountId(rule) || listed) throw UsageError.ExecutionFailed("This $name account is already listed.")
        val config = ProviderAccountConfig(
            accountId = Uuid.random().toString().lowercase(), label = "", email = email,
            probeConfig = values + (rule.accountId.savedAs to accountId), madeBy = folder.madeBy,
        )
        return add(config) ?: throw UsageError.ExecutionFailed("This $name login can't be added.")
    }

    /** Who the plain login is, read the way an added folder's login is. */
    private fun plainAccountId(rule: ProviderDefinition.Accounts.Folder): String? {
        val sources = runCatching { configuration.sources(emptyMap(), isDefault = true) }.getOrNull() ?: emptyList()
        return sources.asSequence().map { makeDataSource(it, id) }.firstNotNullOfOrNull { it.value(rule.accountId.field) }
    }

    /**
     * Who is signed in with these values: the first data source that looks up a key, filled
     * with them. A folder whose key does not answer holds no login, whatever else it holds.
     */
    private fun signedIn(values: Map<String, String>, rule: ProviderDefinition.Accounts.Folder): Pair<String?, String?>? {
        val source = runCatching { configuration.running.dataSourcesForAccount(values) }.getOrNull()
            ?.firstOrNull { it.credential != null } ?: return null
        val live = makeDataSource(source, "$id.new")
        if (!live.hasKey) return null
        return live.value(rule.accountId.field)?.ifEmpty { null } to live.value(rule.email)
    }

    // A list compares by its logins; the card is one thing.
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = id.hashCode()
}
