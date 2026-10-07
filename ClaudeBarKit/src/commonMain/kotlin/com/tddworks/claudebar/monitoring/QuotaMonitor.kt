package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.providers.Account
import com.tddworks.claudebar.providers.ObservableState
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.ProviderDefinition
import com.tddworks.claudebar.providers.ProviderSettingsRepository
import com.tddworks.claudebar.providers.Providers
import com.tddworks.claudebar.providers.RefreshKind
import com.tddworks.claudebar.providers.RefreshOutcome
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.StatusPolicy
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageQuota
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.produceIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/** What the background loop reports. */
public sealed class MonitoringEvent {
    /** A refresh cycle completed. */
    data object Refreshed : MonitoringEvent()

    /** A refresh of one login failed. */
    data class Error(val providerId: String, val error: UsageError) : MonitoringEvent()
}

/**
 * THE CONDUCTOR — refreshes the logins the person watches, alerts when a status changes, and
 * holds what the popover selects. It reads [providers] and watches; adding, deleting and
 * ordering them is `Providers`' (TARGET §2.1). Its own state — the selection, whether it
 * monitors, the hidden quotas — bumps [revision] after every change (MODULAR_DESIGN §5).
 */
public class QuotaMonitor internal constructor(
    /** The providers you keep — each with its logins, in the pane's order (CANONICAL §1). */
    val providers: Providers,
    /** Tells the person about a status change — the composition root adapts alerting to it. */
    private val alerter: QuotaAlerter? = null,
    /** Waits between background refreshes. */
    private val clock: Clock = SystemClock,
    /** Where the quotas each product hides are saved (#140); null keeps none. */
    private val settingsRepository: ProviderSettingsRepository? = null,
    /** Energy awareness; null is the plain timed loop. */
    private val powerState: PowerStateProvider? = null,
    /** The person's status policy, read live — every status reported and alert sent is under it. */
    private val statusPolicy: () -> StatusPolicy = { StatusPolicy.Absolute },
    /** Now, in Unix seconds — what a pace-aware status reads. */
    private val now: () -> Double = { kotlin.time.Clock.System.now().toEpochMilliseconds() / 1000.0 },
    /** Where the background loop runs; [stopMonitoring] cancels it. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    private data class Seen(
        /** Empty until the first login in the lineup is selected. */
        val selectedProviderId: String = "",
        val isMonitoring: Boolean = false,
        /** The quotas each product hides (#140), by product id. */
        val hiddenQuotas: Map<String, Set<String>> = emptyMap(),
    )

    private val state = ObservableState(Seen())

    /** Bumped after the selection, the monitoring switch or a hidden quota changes. */
    val revision: StateFlow<Long> get() = state.revision

    private val lock = SynchronizedObject()

    /** Each login's last status, so an alert goes out only on a change. */
    private val previousStatuses = mutableMapOf<String, QuotaStatus>()

    /** What else reacts to a refreshed login — the Monitor's one extension point. */
    private val refreshObservers = mutableListOf<suspend (Account) -> Unit>()

    private var monitoringJob: Job? = null

    init {
        val hidden = buildMap {
            for (provider in providers.all) {
                if (provider.id in this) continue
                settingsRepository?.hiddenQuotaKeys(provider.id)?.let { put(provider.id, it) }
            }
        }
        state.update { it.copy(hiddenQuotas = hidden) }
        selectFirstEnabledIfNeeded()
    }

    // Hidden quotas (#140)

    /** A login's usage as every surface reads it: without the quotas the person hid for its product. */
    fun usage(of: Account): UsageSnapshot? = of.snapshot?.hiding(hiddenQuotaKeys(of))

    /** The quota keys hidden for a login's product — shared by its accounts. */
    fun hiddenQuotaKeys(of: Account): Set<String> = state.current.hiddenQuotas[of.providerId] ?: emptySet()

    /** Hides or shows one quota for a login's product, saved. Refused — false — when it would hide the last quota the login reports. */
    fun setQuota(key: String, hidden: Boolean, of: Account): Boolean {
        val product = of.providerId
        var keys = state.current.hiddenQuotas[product] ?: emptySet()
        if (hidden) {
            val reported = of.snapshot?.quotas?.map { it.quotaType.quotaKey }?.toSet() ?: emptySet()
            if ((reported - keys - key).isEmpty()) return false
            keys = keys + key
        } else {
            keys = keys - key
        }
        state.update { it.copy(hiddenQuotas = it.hiddenQuotas + (product to keys)) }
        settingsRepository?.setHiddenQuotaKeys(keys, product)
        return true
    }

    // The logins

    /** Every login, on or off, in the pane's order. */
    val logins: List<Account> get() = providers.logins

    /** The enabled logins of enabled providers, in the pane's order — what the pills, menu bar, refreshes and alerts show. */
    val lineup: List<Account> get() = providers.lineup

    /** The login with the given lineup id (`claude`, `codex.<acct>`). */
    fun login(id: String): Account? = providers.login(id)

    /** A login's product, found through the root (TARGET §2.1). */
    fun product(of: Account): Provider? = providers.provider(of = of)

    /** *The name the lineup prints* for a login — its product's to say. */
    fun lineupName(of: Account): String = product(of)?.lineupName(of) ?: of.displayName

    /** What setting a login up takes — its product's words. */
    fun setupNotice(of: Account): ProviderDefinition.Setup =
        product(of)?.setupNotice(of) ?: ProviderDefinition.Setup.fallback(of.displayName, of.lastError)

    /** The dashboard for a login's plan — its product's to say. */
    fun dashboardURL(of: Account): String? = product(of)?.dashboardURL(of)

    // Refreshing

    /** Refreshes every login in the lineup at once. */
    suspend fun refreshAll() = refreshEach(lineup, RefreshKind.INTERACTIVE)

    /** Refreshes one login by its lineup id. */
    suspend fun refresh(providerId: String, kind: RefreshKind = RefreshKind.INTERACTIVE) {
        val login = login(providerId) ?: return
        refreshLogin(login, kind)
    }

    /** Refreshes the given logins once each, in order, duplicates dropped. */
    suspend fun refresh(providerIds: List<String>, kind: RefreshKind = RefreshKind.INTERACTIVE) = coroutineScope {
        for (id in providerIds.distinct()) launch { refresh(id, kind) }
    }

    /** Refreshes every login in the lineup but [except]. */
    suspend fun refreshOthers(except: String) = refreshEach(lineup.filter { it.id != except }, RefreshKind.INTERACTIVE)

    /** Refreshes only the selected login. */
    suspend fun refreshSelected(kind: RefreshKind = RefreshKind.INTERACTIVE) = refresh(selectedProviderId, kind)

    /** Runs [observer] after every successful refresh of a login — so a feature that follows refreshes never edits the Monitor. */
    fun onRefreshed(observer: suspend (Account) -> Unit) {
        synchronized(lock) { refreshObservers += observer }
    }

    private suspend fun refreshEach(logins: List<Account>, kind: RefreshKind) = coroutineScope {
        for (login in logins) launch { refreshLogin(login, kind) }
    }

    /** `kind` tells the provider how much work to do: the loop's `BACKGROUND` skips what nobody glances at and lowers the CLIs' priority (#204). */
    private suspend fun refreshLogin(login: Account, kind: RefreshKind) {
        val product = providers.provider(of = login) ?: return
        if (!product.isAvailable(login)) return
        // A failure is the login's own lastError; nothing to follow.
        val outcome = product.refresh(login, kind) as? RefreshOutcome.Refreshed ?: return
        follow(login, outcome.usage)
    }

    /** Alerts when the login's status changed, then tells every observer. */
    private suspend fun follow(login: Account, usage: UsageSnapshot) {
        // A quota the person hid doesn't page them.
        val status = usage.hiding(hiddenQuotaKeys(login)).overallStatus(statusPolicy(), now())
        val previous = synchronized(lock) { previousStatuses.put(login.id, status) } ?: QuotaStatus.HEALTHY
        if (previous != status) alerter?.alert(login.id, previous, status)
        for (observer in synchronized(lock) { refreshObservers.toList() }) observer(login)
    }

    // Queries

    /** The lowest quota across the lineup. */
    fun lowestQuota(): UsageQuota? = lineup.mapNotNull { usage(it)?.lowestQuota }.minByOrNull { it.percentRemaining }

    /** One login's quota by its key, from the lineup — what the menu bar shows. */
    fun quota(providerId: String, quotaKey: String): UsageQuota? =
        lineup.firstOrNull { it.id == providerId }?.snapshot?.quotaForKey(quotaKey)

    /** The worst status across the lineup. */
    val overallStatus: QuotaStatus
        get() {
            val policy = statusPolicy()
            val now = now()
            return lineup.mapNotNull { usage(it)?.overallStatus(policy, now) }.maxOrNull() ?: QuotaStatus.HEALTHY
        }

    /** One login's status under the person's policy; null with no usage. */
    fun status(of: Account): QuotaStatus? = usage(of)?.overallStatus(statusPolicy(), now())

    /** Whether any login is refreshing. */
    val isRefreshing: Boolean get() = logins.any { it.isSyncing }

    // Selection

    /** The selected login's lineup id (for the popover). */
    var selectedProviderId: String
        get() = state.current.selectedProviderId
        set(value) {
            state.update { it.copy(selectedProviderId = value) }
        }

    /** The selected login, when it is in the lineup. */
    val selectedLogin: Account? get() = selectedProviderId.let { id -> lineup.firstOrNull { it.id == id } }

    /** The selected login's status — the menu-bar icon's. */
    val selectedProviderStatus: QuotaStatus get() = selectedLogin?.let(::status) ?: QuotaStatus.HEALTHY

    /** Selects a login in the lineup; one outside it is ignored. */
    fun selectProvider(id: String) {
        if (lineup.any { it.id == id }) selectedProviderId = id
    }

    /**
     * Selects the tab in the 1-based [position], counted as the popover lists them (⌘1 is the
     * first pill), on its first login — the persisted order (#141). A slot with no tab is ignored.
     */
    fun selectProvider(atPosition: Int) {
        val first = tabs.getOrNull(atPosition - 1)?.accounts?.firstOrNull() ?: return
        selectedProviderId = first.id
    }

    /** The popover's pills: one per product, its enabled logins inside, in the persisted order (#141). */
    val tabs: List<ProductTab> get() = ProductTab.tabs(lineup, providers)

    /** Settings → Providers: every product, on or off, with all its logins (CANONICAL §1). */
    val productTabs: List<ProductTab> get() = ProductTab.tabs(logins, providers)

    /** A product's switch — off hides every login and keeps them; the selection moves off it. */
    fun setProductEnabled(tab: ProductTab, enabled: Boolean) {
        tab.provider.isEnabled = enabled
        if (!enabled) selectFirstEnabledIfNeeded()
    }

    /** One login's own switch; turning off the selected one selects the first in the lineup. */
    fun setProviderEnabled(id: String, enabled: Boolean) {
        val login = login(id) ?: return
        login.isEnabled = enabled
        if (!enabled) selectFirstEnabledIfNeeded()
    }

    /** The tab the selected login belongs to. */
    val selectedTab: ProductTab? get() = selectedProviderId.let { id -> tabs.firstOrNull { it.contains(id) } }

    /** The logins the popover shows: the selected tab's, or the selected login alone. */
    val selectedLogins: List<Account> get() = selectedTab?.accounts ?: listOfNotNull(selectedLogin)

    /** The selected tab's worst status; null while no login has usage. */
    val selectedTabStatus: QuotaStatus? get() = selectedLogins.mapNotNull(::status).maxOrNull()

    /** What the popover's header says about the selected tab. */
    val selectedBadge: ProviderBadgeState get() = ProviderBadgeState.reading(selectedLogins, selectedTabStatus)

    private fun selectFirstEnabledIfNeeded() {
        val lineup = lineup
        if (lineup.none { it.id == selectedProviderId }) lineup.firstOrNull()?.let { selectedProviderId = it.id }
    }

    // Continuous monitoring

    /** Whether the background loop runs. */
    val isMonitoring: Boolean get() = state.current.isMonitoring

    /** The floors the logins refreshed each cycle declare — [providerIds], or the selected one — read per tick so a live data-source switch counts (#204). */
    private fun backgroundRefreshFloors(providerIds: List<String>?): List<Double> =
        (providerIds ?: listOf(selectedProviderId)).mapNotNull { id -> login(id)?.let(::product)?.backgroundRefreshFloorSeconds }

    /**
     * Starts the background loop: each cycle refreshes [providerIds] (once each), or the selected
     * login when none are given, as a `BACKGROUND` refresh; then waits [intervalSeconds] — never
     * under a minute, raised to the slowest provider's floor, doubled on battery. While the
     * display sleeps it waits, and refreshes the moment it wakes. A loop already running is
     * stopped first. The flow ends when [stopMonitoring] is called or its collector stops.
     */
    fun startMonitoring(intervalSeconds: Double = 60.0, providerIds: List<String>? = null): Flow<MonitoringEvent> {
        monitoringJob?.cancel()
        state.update { it.copy(isMonitoring = true) }
        val events = Channel<MonitoringEvent>(Channel.UNLIMITED)
        val job = scope.launch {
            // Power transitions, listened to from the start; none without a power source.
            val power: ReceiveChannel<PowerEvent>? = powerState?.events()?.produceIn(this)
            try {
                while (isActive) {
                    // Asleep: no refresh and no CLI — wait for the wake (#204).
                    while (powerState?.isDisplayAsleep == true && isActive) {
                        power?.receiveCatching()?.getOrNull() ?: break
                    }
                    if (!isActive) break

                    if (providerIds != null) refresh(providerIds, RefreshKind.BACKGROUND) else refreshSelected(RefreshKind.BACKGROUND)
                    events.trySend(MonitoringEvent.Refreshed)

                    var seconds = effectiveInterval(intervalSeconds, backgroundRefreshFloors(providerIds))
                    if (powerState?.isOnBattery == true) seconds *= BATTERY_INTERVAL_MULTIPLIER
                    try {
                        clock.sleep(seconds)
                    } catch (stopped: CancellationException) {
                        break
                    } catch (failed: Exception) {
                        AppLog.monitor.warning("Monitoring stopped: the clock failed (${failed.message})")
                        break
                    }
                }
            } finally {
                power?.cancel()
            }
        }
        // Closed however the loop ends — even when it is stopped before it starts.
        job.invokeOnCompletion { events.close() }
        monitoringJob = job
        return events.consumeAsFlow().onCompletion { job.cancel() }
    }

    /** Stops the background loop. */
    fun stopMonitoring() {
        state.update { it.copy(isMonitoring = false) }
        monitoringJob?.cancel()
        monitoringJob = null
    }

    companion object {
        /** Background refresh never polls faster than once a minute (energy, #67). */
        const val MINIMUM_INTERVAL_SECONDS = 60.0

        /** On battery the cadence stretches this much (#204); plugging in restores it. */
        const val BATTERY_INTERVAL_MULTIPLIER = 2

        /** A requested interval, never under the one-minute floor. */
        fun clampedInterval(seconds: Double): Double = maxOf(seconds, MINIMUM_INTERVAL_SECONDS)

        /** One tick's wait: the requested interval clamped to a minute, then raised to the slowest provider's floor (Claude's API: 15 minutes, #204). */
        fun effectiveInterval(requestedSeconds: Double, floors: List<Double>): Double =
            maxOf(clampedInterval(requestedSeconds), floors.maxOrNull() ?: 0.0)
    }
}
