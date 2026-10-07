package com.tddworks.claudebar.kit

import com.tddworks.claudebar.activity.FileHookSettings
import com.tddworks.claudebar.activity.HookHttpServer
import com.tddworks.claudebar.activity.HookInstaller
import com.tddworks.claudebar.activity.InUseAlert
import com.tddworks.claudebar.activity.InUseAnnouncer
import com.tddworks.claudebar.activity.LoginShell
import com.tddworks.claudebar.activity.NewSessions
import com.tddworks.claudebar.activity.PortDiscovery
import com.tddworks.claudebar.activity.SessionAnnouncer
import com.tddworks.claudebar.activity.SessionMonitor
import com.tddworks.claudebar.activity.SessionTracking
import com.tddworks.claudebar.activity.ShellSetup
import com.tddworks.claudebar.activity.SystemProcessLiveness
import com.tddworks.claudebar.alerting.InUseNotifications
import com.tddworks.claudebar.alerting.NotificationAlerter
import com.tddworks.claudebar.alerting.NotifyGatewayClient
import com.tddworks.claudebar.alerting.NotifyPublisher
import com.tddworks.claudebar.alerting.NotifyQuotaReading
import com.tddworks.claudebar.alerting.NotifySettings
import com.tddworks.claudebar.alerting.notifyGatewayHttpClient
import com.tddworks.claudebar.alerting.QuotaAlertNotifications
import com.tddworks.claudebar.alerting.QuotaAlertSettings
import com.tddworks.claudebar.alerting.QuotaAlerts
import com.tddworks.claudebar.alerting.UserNotificationsAlertSender
import com.tddworks.claudebar.datasources.process.AccountSignIn
import com.tddworks.claudebar.datasources.process.DiskLoginFolders
import com.tddworks.claudebar.datasources.process.MacProcesses
import com.tddworks.claudebar.datasources.process.PosixSignInProcess
import com.tddworks.claudebar.datasources.systemDataSources
import com.tddworks.claudebar.leaderboard.CredentialSigningKeyStore
import com.tddworks.claudebar.leaderboard.JsonLeaderboardSettings
import com.tddworks.claudebar.leaderboard.Leaderboard
import com.tddworks.claudebar.leaderboard.LeaderboardHttpClient
import com.tddworks.claudebar.leaderboard.LeaderboardMembership
import com.tddworks.claudebar.leaderboard.LeaderboardUploader
import com.tddworks.claudebar.leaderboard.MemberCalendar
import com.tddworks.claudebar.leaderboard.SystemRandomBytes
import com.tddworks.claudebar.leaderboard.SystemUtcOffset
import com.tddworks.claudebar.leaderboard.leaderboardHttpEngine
import com.tddworks.claudebar.monitoring.PowerEvent
import com.tddworks.claudebar.monitoring.QuotaAlerter
import com.tddworks.claudebar.monitoring.QuotaMonitor
import com.tddworks.claudebar.monitoring.SystemPowerStateProvider
import com.tddworks.claudebar.providers.BuiltInDefinitions
import com.tddworks.claudebar.providers.CLIGuestPassSource
import com.tddworks.claudebar.providers.DiskLoginsInUse
import com.tddworks.claudebar.providers.DiskPaths
import com.tddworks.claudebar.providers.Engine
import com.tddworks.claudebar.providers.ExtensionSettingsUpgrade
import com.tddworks.claudebar.providers.FileLedgerStore
import com.tddworks.claudebar.providers.FolderDefinitionFiles
import com.tddworks.claudebar.providers.JsonProviderSettings
import com.tddworks.claudebar.providers.ProviderCatalog
import com.tddworks.claudebar.providers.ProviderDefinition
import com.tddworks.claudebar.providers.ProviderFactory
import com.tddworks.claudebar.providers.ProviderVault
import com.tddworks.claudebar.providers.ProviderWorkshop
import com.tddworks.claudebar.providers.Providers
import com.tddworks.claudebar.providers.SystemClipboard
import com.tddworks.claudebar.providers.UserDefaultsLegacyStore
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.StatusPolicy
import com.tddworks.claudebar.storage.KeychainCredentials
import com.tddworks.claudebar.storage.Revision
import com.tddworks.claudebar.storage.SettingsFile
import com.tddworks.claudebar.storage.UserDefaultsCredentials
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import platform.Foundation.NSDate
import platform.Foundation.NSHomeDirectory
import platform.Foundation.timeIntervalSince1970

/**
 * The kit on this Mac: its real files, CLIs, Keychain, servers and notifications.
 * [definitions] is the folder the built-in provider definitions ship in — the app bundle's.
 */
public fun ClaudeBarCore.Companion.start(definitions: String, home: String = NSHomeDirectory()): ClaudeBarCore {
    val root = home.trimEnd('/')
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val now = { NSDate().timeIntervalSince1970 }
    val settingsFile = SettingsFile("$root/.claudebar/settings.json")
    val legacy = UserDefaultsLegacyStore()
    val keychain = KeychainCredentials()
    val fallback = UserDefaultsCredentials()
    val alertSender = UserNotificationsAlertSender()

    // Every provider is a definition on disk — the bundle, Add Provider's ~/.claudebar/providers
    // and ~/.claudebar/extensions — found by the catalog and made on one engine; no line here
    // names a provider (TARGET_ARCHITECTURE §10).
    val settings = JsonProviderSettings(settingsFile, legacy)
    val vault = ProviderVault(keychain, legacy)
    val host = MacProcesses.host
    val connections = systemDataSources(home, now)
    val engine = Engine(
        settings = settings,
        connections = connections,
        home = home,
        environment = { host.machine.environment[it] },
        folders = DiskLoginFolders,
        paths = DiskPaths(home),
        isExecutable = host.files::isExecutable,
        locate = host.locator::locate,
        vault = vault,
        loginsInUse = DiskLoginsInUse("$root/.claudebar/in-use"),
        signIn = AccountSignIn(PosixSignInProcess, DiskLoginFolders, host.locator::locate) { host.machine.environment },
        ledger = FileLedgerStore("$root/.claudebar/usage-history"),
        guestPasses = CLIGuestPassSource.runner(host, SystemClipboard()),
        now = now,
    )
    val builtIns = BuiltInDefinitions(FolderDefinitionFiles(definitions))
    val catalog = ProviderCatalog(builtIns, "$root/.claudebar/providers", "$root/.claudebar/extensions")
    val found = catalog.detect()
    // What was saved for an extension before it was a definition moves once.
    ExtensionSettingsUpgrade.run(
        found.filter { it.profile.origin == com.tddworks.claudebar.providers.ProviderProfile.Origin.EXTENSION },
        settingsFile, settings, vault, legacy,
    )
    val factory = ProviderFactory(engine, builtIns)
    val products = factory.make(found)
    val providers = Providers(products, catalog, settings, vault, factory.customs) { definition: ProviderDefinition -> factory.make(definition) }

    // Status changes and *Quota alerts* follow every refresh, on the person's burn-rate setting (#357).
    val statusPolicy = {
        StatusPolicy.from(
            burnRateWarningEnabled = (settingsFile.read("app.burnRateWarningEnabled") as? JsonPrimitive)?.booleanOrNull ?: false,
            burnRateThreshold = (settingsFile.read("app.burnRateThreshold") as? JsonPrimitive)?.doubleOrNull ?: 1.5,
        )
    }
    val power = SystemPowerStateProvider()
    lateinit var monitor: QuotaMonitor
    val notifications = NotificationAlerter(alertSender) { id -> monitor.login(id)?.let(monitor::lineupName) }
    monitor = QuotaMonitor(
        providers = providers,
        alerter = object : QuotaAlerter {
            override suspend fun requestPermission() = notifications.requestPermission()
            override suspend fun alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) =
                notifications.alert(providerId, previousStatus, currentStatus)
        },
        settingsRepository = settings,
        powerState = power,
        statusPolicy = statusPolicy,
        now = now,
        scope = scope,
    )

    // *In use*: every product whose definition declares it — chosen by the definition, never by a name.
    val inUseNotifications = InUseNotifications(alertSender)
    val newSessions = NewSessions(
        products = providers.all,
        shellLines = ShellSetup(providers.all.mapNotNull { it.inUse?.command }, home),
        announcer = object : InUseAnnouncer {
            override suspend fun announce(alert: InUseAlert) = inUseNotifications.announce(
                InUseNotifications.News(
                    InUseNotifications.Kind.valueOf(alert.kind.name), alert.providerName, alert.from, alert.to,
                    alert.fromLeft, alert.toLeft, alert.link,
                ),
            )
        },
        shell = LoginShell.login(host.machine.environment["SHELL"]),
    )
    monitor.onRefreshed { refreshed -> newSessions.review(refreshed) }
    val quotaAlerts = QuotaAlerts(QuotaAlertSettings(settingsFile), QuotaAlertNotifications(alertSender))
    monitor.onRefreshed { refreshed -> quotaAlerts.review(refreshed.id, monitor.lineupName(refreshed), monitor.usage(refreshed)) }

    // The leaderboard uploads only once the person joined; until then it reads nothing.
    val calendar = MemberCalendar(SystemUtcOffset())
    val random = SystemRandomBytes()
    val api = LeaderboardHttpClient(leaderboardHttpEngine(), calendar, random, now = now)
    val logs = MonitorTokenLogs(monitor)
    val membership = LeaderboardMembership(
        api, CredentialSigningKeyStore(keychain, fallback), JsonLeaderboardSettings(settingsFile), logs, calendar, random,
    )
    val uploader = LeaderboardUploader(membership, logs, api, calendar, now)
    val leaderboard = Leaderboard(
        membership, uploader, api, logs, calendar,
        wakes = power.events().filter { it == PowerEvent.DID_WAKE }.map { },
        now = now, scope = scope,
    )

    val notifySettings = NotifySettings(settingsFile, keychain, fallback)

    // Claude Code's sessions, from its hooks.
    val hookSettings = FileHookSettings(settingsFile)
    val sessions = SessionMonitor()
    val tracking = SessionTracking(
        sessions = sessions,
        receiver = HookHttpServer(PortDiscovery.inHome(home), defaultPort = hookSettings.hookPort()),
        liveness = SystemProcessLiveness(),
        announcer = SessionAnnouncer { title, body, category -> alertSender.send(title, body, category) },
        now = now,
        scope = scope,
    )
    return ClaudeBarCore(
        monitor = monitor,
        workshop = ProviderWorkshop(providers, catalog, builtIns, connections, vault),
        factory = factory,
        providerSettings = settings,
        vault = vault,
        forgetCLIs = host.locator::invalidateCaches,
        newSessions = newSessions,
        quotaAlerts = quotaAlerts,
        notifications = notifications,
        leaderboard = leaderboard,
        notifySettings = notifySettings,
        notifyPublisher = NotifyPublisher(
            settings = notifySettings,
            publisher = NotifyGatewayClient(notifyGatewayHttpClient()),
            readings = {
                monitor.lineup.flatMap { login ->
                    monitor.usage(login)?.quotas.orEmpty().map { NotifyQuotaReading(login.id, monitor.lineupName(login), it) }
                }
            },
            statusPolicy = statusPolicy,
            changes = Revision.any.map { },
            now = now,
            scope = scope,
        ),
        settingsFile = settingsFile,
        sessions = sessions,
        sessionTracking = tracking,
        hookSettings = hookSettings,
        hookInstaller = HookInstaller.inHome(home),
    )
}
