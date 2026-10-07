package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSource
import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.LoginFolders
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.datasources.process.AccountSignIn
import com.tddworks.claudebar.datasources.process.FetchContext
import com.tddworks.claudebar.datasources.process.QualityOfService
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Clock

/**
 * THE PRODUCT — Codex, Claude, a gateway someone added — and THE lifecycle, once for every
 * login of it. What a provider *is* lives in its definition, how it fetches in its data
 * sources; who is signed in, and what we last saw for them, lives in its [accounts].
 *
 * Every login runs the same definition: an added one with `accounts.patch` merged in and its
 * values filling `{{account.x}}`, made live once and kept, so each login has its own cache and
 * rate-limit memory. Overlapping refreshes of one login share one fetch, run in [scope] so a
 * caller that gives up never cancels it for the others.
 */
internal class Provider(
    val definition: ProviderDefinition,
    internal val settings: MultiAccountSettingsRepository,
    saved: List<ProviderAccountConfig> = emptyList(),
    /** Makes a definition live for one login, by its lineup id — so its keys come from that login's corner of the vault. */
    private val makeDataSource: (DataSourceDefinition, String) -> DataSource,
    /** *Share Claude Code*, for a provider whose plan can issue guest passes. */
    val guestPasses: GuestPasses? = null,
    usageHistory: UsageHistory? = null,
    makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)? = null,
    folders: LoginFolders,
    loginsInUse: LoginsInUse? = null,
    vault: SecretVault? = null,
    paths: PathChecking,
    isExecutable: (String) -> Boolean,
    locate: (String) -> String?,
    signIn: AccountSignIn? = null,
    signInRoot: String = "",
    private val now: () -> Double = { Clock.System.now().toEpochMilliseconds() / 1000.0 },
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    /** *The provider's Settings page* — data source, settings form, CLI location. Owned here; it knows no one above it. */
    val configuration = Configuration(definition, settings, vault, paths, isExecutable, locate)

    /** *The Accounts card* — its logins, in your order. Owned here; it reports, never reaches up. */
    val accounts = Accounts(definition, settings, configuration, folders, makeDataSource, makeUsageHistory, signIn, signInRoot)

    private val lock = SynchronizedObject()

    /** Each login's live data sources, and the configuration revision they were made at — made here and nowhere else. */
    private val bound = mutableMapOf<String, Pair<Int, List<DataSource>>>()
    private val refreshes = mutableMapOf<String, Deferred<UsageSnapshot>>()

    /** *The product's switch* (CANONICAL §1). */
    private val enabled = ObservableState(productSwitch(definition, settings, saved))

    /** Bumped when the product's switch changes; its pages and logins keep their own. */
    val revision: StateFlow<Long> get() = enabled.revision

    /**
     * *The product's switch* — Claude on or off. Off hides every login (no pill, menu-bar
     * entry, refresh or alert) and keeps each login and its own *Pause*.
     */
    var isEnabled: Boolean
        get() = enabled.current
        set(value) {
            enabled.update { value }
            settings.setEnabled(value, id)
        }

    /** *In use* — which login new terminal sessions start with; null when this product's CLI can't be started on a login's folder. */
    val inUse: InUse?

    init {
        accounts.start(usageHistory, guestPasses, ::follow, saved)
        val call = definition.accounts?.signIn
        inUse = if (loginsInUse != null && call != null && definition.accounts?.folder != null) {
            InUse(accounts, definition.id, definition.profile.name, TerminalCommand(call.cli, call.homeVariable),
                loginsInUse, SwitchWhenLow(definition.id, settings))
        } else {
            null
        }
    }

    val id: String get() = definition.id
    val name: String get() = definition.profile.name

    /** The plain login the CLI already uses. */
    val defaultAccount: Account get() = accounts.plain

    // Following the Accounts card

    private fun follow(change: Accounts.Change) {
        when (change) {
            // Supplying a login's key opts its product in (an opt-in provider).
            is Accounts.Change.Added -> if (change.byKey) isEnabled = true
            is Accounts.Change.Removed -> {
                inUse?.forget(change.account)
                val running = synchronized(lock) {
                    bound.remove(change.account.id)
                    refreshes.remove(change.account.id)
                }
                running?.cancel()
            }
        }
    }

    // Data sources

    /** The live data sources a login runs — made from the configuration at its current revision, here and nowhere else. */
    fun dataSources(account: Account): List<DataSource> = synchronized(lock) {
        val revision = configuration.sourcesRevision
        bound[account.id]?.takeIf { it.first == revision }?.let { return@synchronized it.second }
        try {
            val sources = configuration.sources(account.values, account.isDefault).map { makeDataSource(it, account.id) }
            bound[account.id] = revision to sources
            sources
        } catch (error: Exception) {
            AppLog.providers.error("${definition.id}: can't run account ${account.id}: ${error.message}")
            emptyList()
        }
    }

    /** Whether a data source's key lookup finds a key for a login — what a config card shows as *credentials found*. */
    fun hasKey(kind: String, account: Account? = null): Boolean = dataSource(kind, account ?: defaultAccount)?.hasKey ?: false

    /** *TODAY'S USAGE* — the plain login's. */
    val usageHistory: UsageHistory? get() = defaultAccount.usageHistory

    // What only the product knows about one of its logins

    /** In the lineup — pills, menu bar, refreshes, alerts: the login is on, and so is its product. */
    fun isInLineup(account: Account): Boolean = account.isEnabled && isEnabled

    /**
     * *The name the lineup prints* — on a pill, the menu bar, an alert: the product's while it
     * has one login to tell apart, else the login's own (TARGET §2.1). Pages never re-decide it.
     */
    fun lineupName(account: Account): String = if (accounts.hasSeveral) account.displayName else name

    /** The dashboard for the plan a login's last usage reported (#328). */
    fun dashboardURL(account: Account): String? = definition.profile.links.dashboard(
        account.snapshot?.accountTier, configuration.settingFills(if (account.isDefault) emptyMap() else account.values),
    )

    /** What setting a login up takes: the definition's words, or its name and what failed when the definition says nothing. */
    fun setupNotice(account: Account): ProviderDefinition.Setup =
        definition.setup ?: ProviderDefinition.Setup.fallback(lineupName(account), account.lastError)

    /** A data source that serves cached usage sets how often the background may ask (Claude's API: 15 minutes, #204). */
    val backgroundRefreshFloorSeconds: Double? get() = definition.dataSource(configuration.activeKind)?.cache?.ttl

    /** The worst quota health across the enabled logins. */
    val status: QuotaStatus get() = accounts.filter { it.isEnabled }.maxOfOrNull { it.status } ?: QuotaStatus.HEALTHY

    /**
     * *Test Connection* — the active data source looks up the key and fetches for a login (the
     * default unless named), stopping BEFORE mapping: what came back, or which step failed. An
     * explicit test checks a CLI session the way an explicit refresh does (#216).
     */
    suspend fun testConnection(account: Account? = null): ConnectionOutcome {
        val active = dataSource(configuration.activeKind, account ?: defaultAccount)
            ?: return ConnectionOutcome.Failed(DataSourceError(DataSourceError.Step.FETCH, UsageError.NoData))
        return try {
            val response = active.fetchResponse()
            if (active.definition.verifyBeforeBackground) markVerified()
            ConnectionOutcome.Answered(response)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: DataSourceError) {
            ConnectionOutcome.Failed(failure)
        } catch (error: Exception) {
            ConnectionOutcome.Failed(DataSourceError(DataSourceError.Step.FETCH, UsageError.ExecutionFailed(error.message ?: error.toString())))
        }
    }

    // Refresh — one login at a time

    /** Ready when the active data source is — or, failing that, the fallback it would hand over to. */
    suspend fun isAvailable(account: Account): Boolean = withContext(Dispatchers.IO) {
        val active = startingDataSource(account) ?: return@withContext false
        if (active.isReady()) return@withContext true
        // No key here, but the data source it hands a missing key to is ready.
        val handOff = active.handOffWithoutKey?.let { dataSource(it, account) }
        if (handOff != null && handOff.isReady()) return@withContext true
        enabledFallback(active, account)?.isReady() ?: false
    }

    /**
     * Fetches a login's usage with the active data source and follows its hand-offs and
     * fallback until one answers. A failure keeps the last usage on screen and reports the first
     * real failure — not a hand-off, and not a fallback's, which would send the person chasing
     * the wrong problem.
     */
    suspend fun refresh(account: Account, kind: RefreshKind = RefreshKind.INTERACTIVE): RefreshOutcome {
        val active = startingDataSource(account) ?: return RefreshOutcome.Failed(UsageError.NoData)
        // Held back until one explicit refresh succeeded (#216): a CLI that was never signed in may open a browser login on its own.
        if (kind != RefreshKind.INTERACTIVE && active.definition.verifyBeforeBackground && !isVerified(account)) {
            account.snapshot?.let { return RefreshOutcome.Refreshed(it) }
            val error = UsageError.ExecutionFailed(active.definition.unverifiedMessage ?: "Not checked yet. Click Refresh.")
            account.lastError = error
            return RefreshOutcome.Failed(error)
        }
        // The background poll runs its CLIs at a low priority, on efficiency cores (#204).
        val priority = if (kind == RefreshKind.BACKGROUND) FetchContext(QualityOfService.UTILITY) else EmptyCoroutineContext
        // Overlapping refreshes of one login share one result.
        var started = false
        val running = synchronized(lock) {
            refreshes[account.id] ?: scope.async(priority) {
                if (definition.together) runTogether(account) else run(account, active)
            }.also {
                refreshes[account.id] = it
                started = true
            }
        }
        return try {
            val usage = running.await()
            if (kind == RefreshKind.INTERACTIVE && active.definition.verifyBeforeBackground) markVerified()
            RefreshOutcome.Refreshed(usage)
        } catch (cancelled: CancellationException) {
            // The caller gave up — or the login was removed while it was being refreshed.
            currentCoroutineContext().ensureActive()
            RefreshOutcome.Failed(account.lastError ?: UsageError.NoData)
        } catch (failure: Exception) {
            RefreshOutcome.Failed(account.lastError ?: failure.asUsageError())
        } finally {
            if (started) synchronized(lock) { if (refreshes[account.id] === running) refreshes.remove(account.id) }
        }
    }

    // Private

    private fun dataSource(kind: String, account: Account): DataSource? = dataSources(account).firstOrNull { it.kind == kind }

    /** Where a login's refresh starts: the active data source — or, when the login's patch left it out, the next one along its fallback chain. */
    private fun startingDataSource(account: Account): DataSource? {
        var kind: String? = configuration.activeKind
        val seen = mutableSetOf<String>()
        while (kind != null && seen.add(kind)) {
            dataSource(kind, account)?.let { return it }
            kind = definition.dataSource(kind)?.fallback?.to
        }
        return null
    }

    private suspend fun run(account: Account, start: DataSource): UsageSnapshot {
        var current = start
        account.isSyncing = true
        try {
            val tried = mutableSetOf(current.kind)
            var reported: Throwable? = null
            while (true) {
                try {
                    val usage = current.fetchUsage()
                    return account.succeed(identified(usage, account), current.kind)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    val reason = reasonOf(error)
                    // A rate limit is not a reason to hit another endpoint.
                    if (reason is UsageError.RateLimited) {
                        reported = reported ?: error
                        break
                    }
                    val tag = reason?.tag
                    val next = tag?.let { current.definition.fallbackOn[it] }
                    val handOff = next?.takeIf { it !in tried }?.let { dataSource(it, account) }
                    if (next != null && handOff != null) {
                        AppLog.probes.info("${account.id} ${current.kind} handed off to $next ($tag)")
                        tried += next
                        current = handOff
                        continue
                    }
                    reported = reported ?: error
                    val fallback = enabledFallback(current, account)
                    if (fallback != null && fallback.kind !in tried) {
                        AppLog.probes.warning("${account.id} ${current.kind} failed (${error.message}), trying ${fallback.kind}")
                        tried += fallback.kind
                        current = fallback
                        continue
                    }
                    break
                }
            }
            if (reported != null && tried.size > 1) {
                AppLog.probes.info("${account.id}: every data source failed; reporting ${reported.message}")
            }
            account.fail(reported ?: UsageError.NoData)
            throw account.lastError ?: UsageError.NoData
        } finally {
            account.isSyncing = false
        }
    }

    /**
     * `together` — every data source of the login answers at once; the usage is their union in
     * the definition's order. A failed one is left out of it and shows beside it as fetch
     * health; the refresh fails only when all do.
     */
    private suspend fun runTogether(account: Account): UsageSnapshot {
        account.isSyncing = true
        try {
            val sources = dataSources(account)
            val results: List<Result<UsageSnapshot>> = coroutineScope {
                sources.map { source ->
                    async {
                        try {
                            Result.success(source.fetchUsage())
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            Result.failure(error)
                        }
                    }
                }.awaitAll()
            }
            val answered = results.mapNotNull { it.getOrNull() }
            val first = answered.firstOrNull()
            if (first == null) {
                val error = results.firstNotNullOfOrNull { it.exceptionOrNull() } ?: UsageError.NoData
                account.fail(error)
                throw account.lastError ?: error
            }
            val metrics = answered.flatMap { it.extensionMetrics ?: emptyList() }
            val union = UsageSnapshot(
                providerId = first.providerId,
                quotas = answered.flatMap { it.quotas },
                capturedAtSeconds = now(),
                accountEmail = answered.firstNotNullOfOrNull { it.accountEmail },
                accountOrganization = null,
                loginMethod = null,
                accountTier = answered.firstNotNullOfOrNull { it.accountTier },
                costUsage = answered.firstNotNullOfOrNull { it.costUsage },
                dailyUsageReport = null,
                extensionMetrics = metrics.ifEmpty { null },
            )
            val kind = sources.indices.firstOrNull { results[it].isSuccess }?.let { sources[it].kind }
            val usage = account.succeed(identified(union, account), kind ?: definition.defaultDataSource)
            results.firstNotNullOfOrNull { it.exceptionOrNull() }?.let(account::noteFailure)
            return usage
        } finally {
            account.isSyncing = false
        }
    }

    /** An added login is checked by being added; the default login once an explicit refresh succeeds, remembered as `<id>.verifiedAtLeastOnce`. */
    private fun isVerified(account: Account): Boolean = !account.isDefault || settings.isOn(VERIFIED_KEY, definition.id) == true

    private fun markVerified() {
        if (settings.isOn(VERIFIED_KEY, definition.id) == true) return
        settings.setOn(true, VERIFIED_KEY, definition.id)
    }

    /** The usage as this login's: its id on every quota, its saved email when the source named none. */
    private fun identified(usage: UsageSnapshot, account: Account): UsageSnapshot {
        if (usage.providerId == account.id && !(usage.accountEmail == null && account.email != null)) return usage
        return usage.copy(
            providerId = account.id,
            quotas = usage.quotas.map { quota ->
                UsageQuota(
                    quota.percentRemaining, quota.quotaType, account.id, quota.resetsAtSeconds, quota.resetText, quota.windowSeconds,
                    quota.dollarRemainingNanos, quota.dollarUsedNanos, quota.dollarCapNanos, quota.group, quota.compactTitle,
                    quota.menuBarTitle, quota.currency,
                )
            },
            accountEmail = usage.accountEmail ?: account.email,
        )
    }

    /** The fallback a data source names, unless a provider setting turns it off. */
    private fun enabledFallback(source: DataSource, account: Account): DataSource? {
        val fallback = source.definition.fallback ?: return null
        if (!configuration.isFallbackEnabled(source.kind)) return null
        return dataSource(fallback.to, account)
    }

    companion object {
        /** The plain login's own *Pause* — apart from the product's switch, which keeps the key the plain login used to have. */
        const val PLAIN_LOGIN_KEY = "plainLoginEnabled"
        private const val VERIFIED_KEY = "verifiedAtLeastOnce"

        internal fun reasonOf(error: Throwable): UsageError? = (error as? DataSourceError)?.reason ?: (error as? UsageError)

        /**
         * The product's switch, read once from before it had its own: the old `<id>.isEnabled`
         * was the plain login's. Off while another login of it was on meant *the plain login was
         * paused* — kept as its pause, the product on; otherwise it meant *the product was off*.
         * Recorded once, by the plain login's own setting.
         */
        private fun productSwitch(definition: ProviderDefinition, settings: MultiAccountSettingsRepository, saved: List<ProviderAccountConfig>): Boolean {
            val id = definition.id
            val on = settings.isEnabled(id, definition.enabledByDefault)
            if (settings.isOn(PLAIN_LOGIN_KEY, id) != null) return on
            val anotherOn = saved.any { settings.isEnabled(it.toProviderAccount(id).id, definition.enabledByDefault) }
            if (!on && anotherOn) {
                settings.setOn(false, PLAIN_LOGIN_KEY, id)
                settings.setEnabled(true, id)
                return true
            }
            settings.setOn(true, PLAIN_LOGIN_KEY, id)
            return on
        }
    }
}
