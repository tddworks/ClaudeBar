import DataSources
import Diagnostics
import Quotas
import Foundation
import Observation

/// THE PRODUCT — Codex, Claude, a gateway someone added — and THE lifecycle,
/// once for every login of it. What a provider *is* lives in its definition,
/// how it fetches in its data sources; who is signed in, and what we last saw
/// for them, lives in its `accounts`.
///
/// Every login runs the same definition: an added one with `accounts.patch`
/// merged in and its values filling `{{account.x}}`, made live once and kept,
/// so each login has its own cache and rate-limit memory.
@MainActor
@Observable
public final class Provider {
    public let definition: ProviderDefinition

    /// *The provider's Settings page* — data source, settings form, CLI
    /// location. Owned here; it knows no one above it (TARGET §2.1).
    public let configuration: Configuration
    /// *The Accounts card* — its logins, in your order, and adding, removing,
    /// renaming and moving them. Owned here; it reports, never reaches up.
    public let accounts: Accounts

    /// The plain login the CLI already uses.
    public var defaultAccount: Account { accounts.plain }

    /// *Share Claude Code*, for a provider whose plan can issue guest passes.
    public let guestPasses: GuestPasses?

    let settings: any MultiAccountSettingsRepository
    /// Makes a definition live for one login, by its lineup id — so its
    /// keys come from that login's corner of the vault.
    private let makeDataSource: (DataSourceDefinition, String) -> DataSource
    /// *The product's switch* — Claude on or off. Off hides every login (no
    /// pill, menu-bar entry, refresh or alert) and keeps each login and its
    /// own *Pause* (CANONICAL §1: the product's switch).
    public var isEnabled: Bool {
        didSet { settings.setEnabled(isEnabled, forProvider: id) }
    }

    /// The plain login's own *Pause* — apart from the product's switch, which
    /// keeps the key the plain login used to have.
    static let plainLoginKey = "plainLoginEnabled"

    /// *In use* — which login new terminal sessions start with; `nil` when
    /// this product's CLI can't be started on a login's folder.
    public private(set) var inUse: InUse?
    /// Each login's live data sources, and the configuration revision they
    /// were made at — made in this one place, remade when older.
    @ObservationIgnored private var bound: [String: (revision: Int, sources: [DataSource])] = [:]
    @ObservationIgnored private var refreshTasks: [String: Task<UsageSnapshot, Error>] = [:]

    /// - Parameter makeDataSource: makes a definition live — the real
    ///   connections in the app, stubbed ones in tests.
    public init(
        definition: ProviderDefinition,
        settings: any MultiAccountSettingsRepository,
        accounts saved: [ProviderAccountConfig] = [],
        makeDataSource: @escaping (DataSourceDefinition, String) -> DataSource,
        guestPasses: GuestPasses? = nil,
        usageHistory: UsageHistory? = nil,
        makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)? = nil,
        folders: any LoginFolders = DiskLoginFolders(),
        loginsInUse: (any LoginsInUse)? = nil,
        vault: (any SecretVault)? = nil,
        paths: any PathChecking = DiskPaths(),
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        locate: @escaping @Sendable (String) -> String? = { BinaryLocator.which($0) }
    ) {
        self.definition = definition
        self.settings = settings
        self.makeDataSource = makeDataSource
        self.guestPasses = guestPasses
        let configuration = Configuration(definition: definition, settings: settings, vault: vault,
                                          paths: paths, isExecutable: isExecutable, locate: locate)
        self.configuration = configuration
        self.accounts = Accounts(definition: definition, settings: settings, configuration: configuration,
                                 folders: folders, makeDataSource: makeDataSource, makeUsageHistory: makeUsageHistory)
        self.isEnabled = Self.productSwitch(definition, settings: settings, accounts: saved)
        // `Accounts` is public and can outlive this provider: its callback
        // holds it weakly (TARGET §2.1).
        accounts.start(plainHistory: usageHistory, guestPasses: guestPasses,
                       onChange: { [weak self] change in self?.follow(change) }, saved: saved)
        if let loginsInUse, let call = definition.accounts?.signIn, definition.accounts?.folder != nil {
            inUse = InUse(accounts: accounts, productId: definition.id, productName: definition.profile.name,
                          command: TerminalCommand(name: call.cli, variable: call.homeVariable),
                          record: loginsInUse, switchWhenLow: SwitchWhenLow(providerId: definition.id, settings: settings))
        }
    }

    /// The product's switch, read once from before it had its own: the old
    /// `<id>.isEnabled` was the plain login's. Off while another login of it
    /// was on meant *the plain login was paused* — kept as its pause, the
    /// product on; otherwise it meant *the product was off*. Recorded once,
    /// by the plain login's own setting.
    private static func productSwitch(_ definition: ProviderDefinition, settings: any MultiAccountSettingsRepository,
                                      accounts: [ProviderAccountConfig]) -> Bool {
        let id = definition.id
        let on = settings.isEnabled(forProvider: id, defaultValue: definition.enabledByDefault)
        guard settings.isOn(plainLoginKey, forProvider: id) == nil else { return on }
        let anotherOn = accounts.contains {
            settings.isEnabled(forProvider: $0.toProviderAccount(providerId: id).id, defaultValue: definition.enabledByDefault)
        }
        if !on && anotherOn {
            settings.setOn(false, plainLoginKey, forProvider: id)
            settings.setEnabled(true, forProvider: id)
            return true
        }
        settings.setOn(true, plainLoginKey, forProvider: id)
        return on
    }

    /// A provider whose data sources ignore which login they run for — the
    /// default login's keys and every added login's are looked up alike.
    public convenience init(
        definition: ProviderDefinition,
        settings: any MultiAccountSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        makeDataSource: @escaping (DataSourceDefinition) -> DataSource,
        guestPasses: GuestPasses? = nil,
        folders: any LoginFolders = DiskLoginFolders(),
        loginsInUse: (any LoginsInUse)? = nil,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        locate: @escaping @Sendable (String) -> String? = { BinaryLocator.which($0) }
    ) {
        self.init(definition: definition, settings: settings, accounts: accounts,
                  makeDataSource: { source, _ in makeDataSource(source) },
                  guestPasses: guestPasses, folders: folders, loginsInUse: loginsInUse, isExecutable: isExecutable,
                  locate: locate)
    }

    public var id: String { definition.id }
    public var name: String { definition.profile.name }

    // MARK: - Following the Accounts card

    private func follow(_ change: Accounts.Change) {
        switch change {
        case .added(_, let byKey):
            // Supplying a login's key opts its product in (an opt-in provider).
            if byKey { isEnabled = true }
        case .removed(let account):
            inUse?.forget(account)
            bound[account.id] = nil
            refreshTasks[account.id]?.cancel()
            refreshTasks[account.id] = nil
        }
    }

    // MARK: - Data sources

    /// The live data sources a login runs — made from the configuration at
    /// its current revision, here and nowhere else.
    public func dataSources(for account: Account) -> [DataSource] {
        let revision = configuration.revision
        if let made = bound[account.id], made.revision == revision { return made.sources }
        do {
            let sources = try configuration.sources(for: account.values, isDefault: account.isDefault)
                .map { makeDataSource($0, account.id) }
            bound[account.id] = (revision, sources)
            return sources
        } catch {
            AppLog.providers.error("\(definition.id): can't run account \(account.id): \(error.localizedDescription)")
            return []
        }
    }

    /// Whether a data source's key lookup finds a key for a login — what a
    /// config card shows as *credentials found*.
    public func hasKey(for kind: String, account: Account? = nil) -> Bool {
        dataSource(kind, for: account ?? defaultAccount)?.hasKey ?? false
    }

    /// *TODAY'S USAGE* — the plain login's.
    public var usageHistory: UsageHistory? { defaultAccount.usageHistory }

    // MARK: - What only the product knows about one of its logins

    /// In the lineup — pills, menu bar, refreshes, alerts: the login is on,
    /// and so is its product.
    public func isInLineup(_ account: Account) -> Bool { account.isEnabled && isEnabled }

    /// *The name the lineup prints* — on a pill, the menu bar, an alert: the
    /// product's while it has one login to tell apart, else the login's own
    /// (TARGET §2.1). Pages never re-decide it.
    public func lineupName(of account: Account) -> String {
        accounts.hasSeveral ? account.displayName : name
    }

    /// The dashboard for the plan a login's last usage reported (#328).
    public func dashboardURL(of account: Account) -> URL? {
        definition.profile.links.dashboard(for: account.snapshot?.accountTier,
                                           settings: configuration.settingFills(ownValues: account.isDefault ? [:] : account.values))
    }

    /// What setting a login up takes: the definition's words, or its name
    /// and what failed when the definition says nothing.
    public func setupNotice(of account: Account) -> ProviderDefinition.Setup {
        definition.setup ?? .fallback(for: lineupName(of: account), error: account.lastError)
    }

    /// A data source that serves cached usage sets how often the background
    /// may ask (Claude's API: 15 minutes, #204).
    public var backgroundRefreshFloor: Duration? {
        definition.dataSource(configuration.activeKind)?.cache.map { .seconds($0.ttl) }
    }

    /// The worst quota health across the enabled logins.
    public var status: QuotaStatus {
        accounts.filter(\.isEnabled).map(\.status).max() ?? .healthy
    }

    /// *Test Connection* — the active data source looks up the key and
    /// fetches for a login (the default unless named), stopping BEFORE
    /// mapping: what came back, or which step failed. An explicit test checks
    /// a CLI session the way an explicit refresh does (#216).
    public func testConnection(_ account: Account? = nil) async -> Result<Response, DataSourceError> {
        let account = account ?? defaultAccount
        guard let active = dataSource(configuration.activeKind, for: account) else {
            return .failure(DataSourceError(.fetch, .noData))
        }
        do {
            let response = try await active.fetchResponse()
            if active.definition.verifyBeforeBackground {
                markVerified()
            }
            return .success(response)
        } catch let failure as DataSourceError {
            return .failure(failure)
        } catch {
            return .failure(DataSourceError(.fetch, .executionFailed(error.localizedDescription)))
        }
    }

    // MARK: - Refresh — one login at a time

    /// Ready when the active data source is — or, failing that, the fallback
    /// it would hand over to.
    public func isAvailable(_ account: Account) async -> Bool {
        guard let active = startingDataSource(for: account) else { return false }
        if await active.isReady() { return true }
        // No key here, but the data source it hands a missing key to is ready.
        if let kind = active.handOffWithoutKey, let handOff = dataSource(kind, for: account), await handOff.isReady() {
            return true
        }
        guard let fallback = enabledFallback(of: active, for: account) else { return false }
        return await fallback.isReady()
    }

    /// Fetches a login's usage with the active data source and follows its
    /// hand-offs and fallback until one answers. A failure keeps the last
    /// usage on screen and reports the first real failure — not a hand-off,
    /// and not a fallback's, which would send the person chasing the wrong problem.
    @discardableResult
    public func refresh(_ account: Account, _ kind: RefreshKind = .interactive) async throws -> UsageSnapshot {
        guard let active = startingDataSource(for: account) else {
            throw UsageError.noData
        }
        // Held back until one explicit refresh succeeded (#216): a CLI that
        // was never signed in may open a browser login on its own.
        if kind != .interactive, active.definition.verifyBeforeBackground, !isVerified(account) {
            if let snapshot = account.snapshot { return snapshot }
            let error = UsageError.executionFailed(active.definition.unverifiedMessage ?? "Not checked yet. Click Refresh.")
            account.lastError = error
            throw error
        }
        // Overlapping refreshes of one login share one result.
        if let running = refreshTasks[account.id] { return try await running.value }
        let task = Task { definition.together ? try await runTogether(account) : try await run(account, from: active, kind) }
        refreshTasks[account.id] = task
        defer { refreshTasks[account.id] = nil }
        let usage: UsageSnapshot
        do {
            usage = try await task.value
        } catch {
            // Signed out since it was checked: held back again until a click (#525).
            if active.definition.verifyBeforeBackground, Self.isSignedOut(error) {
                forgetVerified()
            }
            throw error
        }
        if kind == .interactive, active.definition.verifyBeforeBackground {
            markVerified()
        }
        return usage
    }

    // MARK: - Private

    private func dataSource(_ kind: String, for account: Account) -> DataSource? {
        dataSources(for: account).first { $0.kind == kind }
    }

    /// Where a login's refresh starts: the active data source — or, when the
    /// login's patch left it out, the next one along its fallback chain.
    private func startingDataSource(for account: Account) -> DataSource? {
        var kind: String? = configuration.activeKind
        var seen: Set<String> = []
        while let current = kind, seen.insert(current).inserted {
            if let source = dataSource(current, for: account) { return source }
            kind = definition.dataSource(current)?.fallback?.to
        }
        return nil
    }

    private func run(_ account: Account, from start: DataSource, _ kind: RefreshKind) async throws -> UsageSnapshot {
        var current = start
        account.isSyncing = true
        defer { account.isSyncing = false }

        var tried: Set = [current.kind]
        var reported: Error?
        while true {
            do {
                let usage = try await current.fetchUsage()
                return account.succeed(identified(usage, for: account), from: current.kind)
            } catch {
                let reason = Self.reason(of: error)
                if case .rateLimited? = reason {
                    // A rate limit is not a reason to hit another endpoint.
                    reported = reported ?? error
                    break
                }
                if let tag = reason?.tag, let next = current.definition.fallbackOn[tag],
                   !tried.contains(next), let handOff = dataSource(next, for: account) {
                    AppLog.probes.info("\(account.id) \(current.kind) handed off to \(next) (\(tag))")
                    tried.insert(next)
                    current = handOff
                    continue
                }
                reported = reported ?? error
                if current.definition.fallback?.sameLogin == true, Self.isSignedOut(error) {
                    // The fallback reads the same login: it is signed out there too (#525).
                    break
                }
                if let fallback = enabledFallback(of: current, for: account), !tried.contains(fallback.kind) {
                    AppLog.probes.warning("\(account.id) \(current.kind) failed (\(error.localizedDescription)), trying \(fallback.kind)")
                    tried.insert(fallback.kind)
                    current = fallback
                    continue
                }
                break
            }
        }
        if let reported, tried.count > 1 {
            AppLog.probes.info("\(account.id): every data source failed; reporting \(reported.localizedDescription)")
        }
        account.fail(reported ?? UsageError.noData)
        throw account.lastError ?? UsageError.noData
    }

    /// `together` — every data source of the login answers at once; the usage
    /// is their union in the definition's order. A failed one is left out of
    /// it and shows beside it as fetch health; the refresh fails only when
    /// all do.
    private func runTogether(_ account: Account) async throws -> UsageSnapshot {
        account.isSyncing = true
        defer { account.isSyncing = false }
        let sources = dataSources(for: account)
        let results = await withTaskGroup(of: (Int, Result<UsageSnapshot, Error>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do { return (index, .success(try await source.fetchUsage())) } catch { return (index, .failure(error)) }
                }
            }
            var results: [(Int, Result<UsageSnapshot, Error>)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let answered = results.compactMap { try? $0.get() }
        guard let first = answered.first else {
            let error = results.lazy.compactMap { result -> Error? in
                if case .failure(let error) = result { return error } else { return nil }
            }.first ?? UsageError.noData
            account.fail(error)
            throw account.lastError ?? error
        }
        let metrics = answered.flatMap { $0.extensionMetrics ?? [] }
        let union = UsageSnapshot(
            providerId: first.providerId,
            quotas: answered.flatMap(\.quotas),
            capturedAt: Date(),
            accountEmail: answered.lazy.compactMap(\.accountEmail).first,
            accountTier: answered.lazy.compactMap(\.accountTier).first,
            costUsage: answered.lazy.compactMap(\.costUsage).first,
            extensionMetrics: metrics.isEmpty ? nil : metrics
        )
        let kind = sources.indices.first { if case .success = results[$0] { return true } else { return false } }.map { sources[$0].kind }
        let usage = account.succeed(identified(union, for: account), from: kind ?? definition.defaultDataSource)
        let failed = results.lazy.compactMap { result -> Error? in
            if case .failure(let error) = result { return error } else { return nil }
        }.first
        if let failed { account.noteFailure(failed) }
        return usage
    }

    /// An added login is checked by being added; the default login once an
    /// explicit refresh succeeds, remembered as `<id>.verifiedAtLeastOnce`.
    private func isVerified(_ account: Account) -> Bool {
        !account.isDefault || settings.isOn("verifiedAtLeastOnce", forProvider: definition.id) == true
    }

    private func markVerified() {
        guard settings.isOn("verifiedAtLeastOnce", forProvider: definition.id) != true else { return }
        settings.setOn(true, "verifiedAtLeastOnce", forProvider: definition.id)
    }

    private func forgetVerified() {
        guard settings.isOn("verifiedAtLeastOnce", forProvider: definition.id) == true else { return }
        settings.setOn(false, "verifiedAtLeastOnce", forProvider: definition.id)
    }

    /// The usage as this login's: its id on every quota, its saved email when
    /// the source named none.
    private func identified(_ usage: UsageSnapshot, for account: Account) -> UsageSnapshot {
        guard usage.providerId != account.id || (usage.accountEmail == nil && account.email != nil) else { return usage }
        return UsageSnapshot(
            providerId: account.id,
            quotas: usage.quotas.map { quota in
                UsageQuota(
                    percentRemaining: quota.percentRemaining, quotaType: quota.quotaType, providerId: account.id,
                    resetsAt: quota.resetsAt, resetText: quota.resetText, windowDuration: quota.windowDuration,
                    dollarRemaining: quota.dollarRemaining, dollarUsed: quota.dollarUsed, dollarCap: quota.dollarCap,
                    group: quota.group, compactTitle: quota.compactTitle, menuBarTitle: quota.menuBarTitle,
                    currency: quota.currency
                )
            },
            capturedAt: usage.capturedAt,
            accountEmail: usage.accountEmail ?? account.email,
            accountOrganization: usage.accountOrganization,
            loginMethod: usage.loginMethod,
            accountTier: usage.accountTier,
            costUsage: usage.costUsage,
            dailyUsageReport: usage.dailyUsageReport,
            extensionMetrics: usage.extensionMetrics
        )
    }

    /// The fallback a data source names, unless a provider setting turns it off.
    private func enabledFallback(of source: DataSource, for account: Account) -> DataSource? {
        guard let fallback = source.definition.fallback, configuration.isFallbackEnabled(from: source.kind) else { return nil }
        return dataSource(fallback.to, for: account)
    }


    static func reason(of error: Error) -> UsageError? {
        (error as? DataSourceError)?.reason ?? (error as? UsageError)
    }

    /// The login needs signing in again — no other data source of it can answer.
    static func isSignedOut(_ error: Error) -> Bool {
        switch reason(of: error) {
        case .authenticationRequired?, .sessionExpired?: true
        default: false
        }
    }
}
