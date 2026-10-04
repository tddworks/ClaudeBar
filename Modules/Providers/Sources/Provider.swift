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

    /// The logins, in the order the person put them — never empty, and one
    /// of them is the default login.
    public private(set) var accounts: [Account] = []
    /// The plain login the CLI already uses — found by being the default,
    /// wherever the person moved it.
    public var defaultAccount: Account { accounts.first(where: \.isDefault)! }

    /// *Share Claude Code*, for a provider whose plan can issue guest passes.
    public let guestPasses: GuestPasses?
    /// *TODAY'S USAGE*, read from the default login's own logs.
    public let usageHistory: UsageHistory?
    /// Makes an added login's usage history from its adapted definition and
    /// lineup id — `nil` when added logins have none.
    private let makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)?
    /// Each added login's own usage history, by lineup id.
    @ObservationIgnored private var usageHistories: [String: UsageHistory] = [:]

    let settings: any MultiAccountSettingsRepository
    /// Makes a definition live for one login, by its lineup id — so its
    /// keys come from that login's corner of the vault.
    private let makeDataSource: (DataSourceDefinition, String) -> DataSource
    /// Where keys typed into *Add Account*'s form are kept.
    private let vault: (any SecretVault)?
    /// Where added logins' folders are made and deleted.
    private let folders: any LoginFolders
    /// What a path setting asks of this Mac.
    private let paths: any PathChecking
    /// Whether a path is a program the CLI location may point at.
    private let isExecutable: @Sendable (String) -> Bool
    /// The definition as it runs here: the CLI at the person's location.
    @ObservationIgnored private var running: ProviderDefinition
    /// *CLI location* — where this provider's CLI lives on this Mac, when the
    /// person chose one (#210). `nil` finds it as usual.
    public private(set) var cliPath: String?
    @ObservationIgnored private var bound: [String: [DataSource]] = [:]
    @ObservationIgnored private var refreshTasks: [String: Task<UsageSnapshot, Error>] = [:]

    /// - Parameter makeDataSource: makes a definition live — the real
    ///   connections in the app, stubbed ones in tests.
    public init(
        definition: ProviderDefinition,
        settings: any MultiAccountSettingsRepository,
        accounts: [ProviderAccountConfig] = [],
        makeDataSource: @escaping (DataSourceDefinition, String) -> DataSource,
        guestPasses: GuestPasses? = nil,
        usageHistory: UsageHistory? = nil,
        makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)? = nil,
        folders: any LoginFolders = DiskLoginFolders(),
        vault: (any SecretVault)? = nil,
        paths: any PathChecking = DiskPaths(),
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.folders = folders
        self.paths = paths
        self.vault = vault
        self.isExecutable = isExecutable
        self.definition = definition
        let cliPath = settings.cliPath(forProvider: definition.id)
        self.cliPath = cliPath
        do {
            self.running = try definition.runningCLI(cliPath ?? "")
        } catch {
            AppLog.providers.error("\(definition.id): can't run the CLI at the saved location: \(error.localizedDescription)")
            self.running = definition
        }
        self.settings = settings
        self.makeDataSource = makeDataSource
        self.guestPasses = guestPasses
        self.usageHistory = usageHistory
        self.makeUsageHistory = makeUsageHistory
        let label = settings.defaultAccountLabel(forProvider: definition.id) ?? ""
        self.accounts = [Account(provider: self, login: ProviderAccount(providerId: definition.id, label: label), values: [:])]
        bind(self.accounts[0])
        for config in accounts {
            attach(config)
        }
        let order = settings.accountOrder(forProvider: definition.id)
        self.accounts = self.accounts.enumerated().sorted { lhs, rhs in
            let (left, right) = (order.firstIndex(of: lhs.element.accountId) ?? order.count + lhs.offset,
                                 order.firstIndex(of: rhs.element.accountId) ?? order.count + rhs.offset)
            return left < right
        }.map(\.element)
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
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.init(definition: definition, settings: settings, accounts: accounts,
                  makeDataSource: { source, _ in makeDataSource(source) },
                  guestPasses: guestPasses, folders: folders, isExecutable: isExecutable)
    }

    // MARK: - CLI location

    /// *CLI location* — runs this provider's CLI from `path` for every login
    /// and for Add Account's sign-in, saved and in effect at once. Empty goes
    /// back to finding the CLI as usual. A path that isn't a program is
    /// refused, and nothing changes.
    public func setCLIPath(_ path: String?) throws {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = trimmed.isEmpty ? nil : NSString(string: trimmed).expandingTildeInPath
        if let chosen, !isExecutable(chosen) {
            throw UsageError.executionFailed("\(chosen) isn't a program ClaudeBar can run. Choose the \(definition.cli ?? name) executable itself.")
        }
        let running = try definition.runningCLI(chosen ?? "")
        self.running = running
        cliPath = chosen
        settings.setCLIPath(chosen, forProvider: id)
        for account in accounts {
            bound[account.id] = try sources(for: account.values, isDefault: account.isDefault).map { makeDataSource($0, account.id) }
        }
    }

    // MARK: - Settings — REGION, API KEY, ENV VAR …

    /// What a setting holds for a login: the login's own value for an
    /// account-scope one, else the provider's saved value, else its default.
    /// Never a secret's: those are kept in the vault, not with these values.
    public func value(of setting: Setting, for account: Account) -> String? {
        value(of: setting, values: account.isDefault ? [:] : account.values)
    }

    /// What to do when the active data source's key lookup finds no key —
    /// the lookup's own hint, when it has one.
    public var keyHint: String? {
        definition.dataSource(activeKind)?.credential?.hint
    }

    /// Whether a value of this setting is saved for a login — a key in the
    /// vault, or a value in settings — never the value itself, so Settings
    /// can say *Saved* without showing a key.
    public func hasSaved(_ setting: Setting, for account: Account) -> Bool {
        if vault?.secret(setting.id, provider: account.id) != nil { return true }
        let own = account.isDefault ? settings.value(setting.id, forProvider: id) : account.values[setting.id]
        return own != nil
    }

    /// Fills in a provider-scope setting — or the default login's value of an
    /// account-scope one — and runs every login with it from the next
    /// refresh. A secret goes to the vault; `nil` or empty forgets it.
    public func set(_ id: String, to value: String?) throws {
        guard let setting = definition.setting(id) else {
            throw UsageError.executionFailed("\(name) has no setting \(id).")
        }
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (value?.isEmpty ?? true) ? nil : value
        if let kept, let problem = setting.check(kept, paths: paths) {
            throw UsageError.executionFailed(problem)
        }
        var entry = SettingEntry()
        if let kept { setting.keep(kept, in: &entry) }
        guard entry.secrets.isEmpty || vault != nil else {
            throw UsageError.executionFailed("ClaudeBar can't keep this key securely here.")
        }
        settings.setValue(entry.values[id], id, forProvider: self.id)
        if entry.secrets.isEmpty {
            vault?.delete(id, provider: self.id)
        } else {
            try keep(entry.secrets, for: self.id)
        }
        for account in accounts { bind(account) }
    }

    /// The definition as the default login runs it — the CLI at its chosen
    /// location and every `{{setting.x}}` filled — so Settings prints
    /// `$MINIMAX_API_KEY`, not the template.
    public var definitionAsRun: ProviderDefinition {
        let sources = (try? sources(for: [:], isDefault: true)) ?? running.dataSources
        return ProviderDefinition(profile: running.profile, cli: running.cli, enabledByDefault: running.enabledByDefault,
                                  dataSources: sources, defaultDataSource: running.defaultDataSource,
                                  accounts: running.accounts, settings: running.settings, usageHistory: running.usageHistory)
    }

    /// Every `{{setting.x}}` a login's data sources are filled with.
    func settingFills(for account: Account) -> [String: String] {
        settingFills(values: account.isDefault ? [:] : account.values)
    }

    private func settingFills(values: [String: String]) -> [String: String] {
        definition.settings.reduce(into: [:]) { fills, setting in
            fills.merge(setting.fills(for: value(of: setting, values: values))) { _, new in new }
        }
    }

    private func value(of setting: Setting, values: [String: String]) -> String? {
        let value = setting.value(from: setting.ownValue(in: values) ?? settings.value(setting.id, forProvider: id))
        return value.isEmpty ? nil : value
    }

    /// Saves keys in the vault under a login, reading each back: an ad-hoc
    /// build's Keychain can seem to save and keep nothing. On a refusal every
    /// key goes back to what it was — a key being replaced is never lost.
    private func keep(_ secrets: [String: String], for login: String) throws {
        let before = secrets.keys.reduce(into: [String: String?]()) { $0[$1] = vault?.secret($1, provider: login) }
        for (name, value) in secrets {
            vault?.save(value, name, provider: login)
            guard vault?.secret(name, provider: login) == value else {
                for (name, previous) in before {
                    vault?.delete(name, provider: login)
                    if let previous { vault?.save(previous, name, provider: login) }
                }
                throw UsageError.executionFailed("ClaudeBar couldn't keep this key securely.")
            }
        }
    }

    /// A login's data sources as data: an added one's patched and filled
    /// with its values, then every login's settings filled in.
    private func sources(for values: [String: String], isDefault: Bool) throws -> [DataSourceDefinition] {
        let sources = isDefault ? running.dataSources : try running.dataSources(forAccount: values)
        let fills = settingFills(values: isDefault ? [:] : values)
        guard !fills.isEmpty else { return sources }
        return try sources.map { try $0.filled(fills, scope: "setting") }
    }

    /// Makes a login's data sources live again — after a setting changed.
    private func bind(_ account: Account) {
        do {
            bound[account.id] = try sources(for: account.values, isDefault: account.isDefault).map { makeDataSource($0, account.id) }
        } catch {
            AppLog.providers.error("\(definition.id): can't run account \(account.id): \(error.localizedDescription)")
        }
    }

    public var id: String { definition.id }
    public var name: String { definition.profile.name }

    // MARK: - Accounts

    /// *Add Account* — a login beside the default one, saved. `nil` when the
    /// definition has no added accounts, the login is already listed, or its
    /// saved values don't fill what the definition needs.
    @discardableResult
    public func add(_ config: ProviderAccountConfig) -> Account? {
        guard let account = attach(config) else { return nil }
        settings.addAccount(config, forProvider: id)
        return account
    }

    /// A saved login made live — at launch, and by `add`.
    @discardableResult
    private func attach(_ config: ProviderAccountConfig) -> Account? {
        let login = config.toProviderAccount(providerId: definition.id)
        guard definition.accounts != nil, !login.isDefault, !accounts.contains(where: { $0.id == login.id }) else {
            return nil
        }
        do {
            bound[login.id] = try sources(for: config.probeConfig, isDefault: false).map { makeDataSource($0, login.id) }
        } catch {
            AppLog.providers.error("\(definition.id): can't run account \(login.id): \(error.localizedDescription)")
            return nil
        }
        let account = Account(provider: self, login: login, values: config.probeConfig, madeBy: config.madeBy)
        accounts.append(account)
        if let makeUsageHistory, let own = definition.usageHistory(forAccount: config.probeConfig) {
            usageHistories[login.id] = makeUsageHistory(own, login.id)
        }
        return account
    }

    /// A login's usage history: the default's, or an added login's own.
    func usageHistory(for account: Account) -> UsageHistory? {
        account.isDefault ? usageHistory : usageHistories[account.id]
    }

    /// *Remove* — forgets the login here and its saved settings, and deletes
    /// the folder only when ClaudeBar made it by signing in. A folder the
    /// person chose is theirs and stays. The default login can't be removed.
    public func remove(_ account: Account) {
        guard !account.isDefault, accounts.contains(where: { $0 === account }) else { return }
        if let folder = account.folder, folder.goesWithAccount {
            folders.delete(folder.url)
        }
        // Whatever of the form went to the vault goes with the login.
        for setting in definition.accountSettings {
            vault?.delete(setting.id, provider: account.id)
        }
        accounts.removeAll { $0.id == account.id }
        bound[account.id] = nil
        usageHistories[account.id] = nil
        refreshTasks[account.id]?.cancel()
        refreshTasks[account.id] = nil
        settings.removeAccount(accountId: account.accountId, forProvider: id)
    }

    /// *Choose Signed-in Folder* — adds the login a folder holds, read by the
    /// definition's own lookups filled with that folder. Refused when the
    /// folder holds no key, or the login is the default one or already listed.
    @discardableResult
    public func addAccount(signedInAt folder: URL) throws -> Account {
        try addAccount(SignedInFolder(url: folder, madeBy: .folder))
    }

    /// What *Add Account*'s form asks for: the account settings the active
    /// data source uses.
    public var accountForm: [Setting] {
        definition.accountSettings.filter { $0.isUsed(by: activeKind) }
    }

    /// *Add Account* by its form — the login's own account-scope settings.
    /// Each value keeps its setting's rule, a default fills a blank, a path
    /// is never another login's, and a secret is kept in the vault under the
    /// new login's id — read back before the login is kept, so nothing is
    /// half saved.
    @discardableResult
    public func addAccount(filling entered: [String: String]) throws -> Account {
        let form = accountForm
        guard !form.isEmpty else { throw UsageError.executionFailed("\(name) has no account form.") }
        var entry = SettingEntry()
        for setting in form {
            let value = setting.value(from: entered[setting.id])
            if let problem = setting.check(value, paths: paths) { throw UsageError.executionFailed(problem) }
            if isTaken(value, by: setting) {
                throw UsageError.executionFailed("Choose a separate folder for \(setting.label) — another \(name) login uses this one.")
            }
            setting.keep(value, in: &entry)
        }
        guard entry.secrets.isEmpty || vault != nil else {
            throw UsageError.executionFailed("ClaudeBar can't keep this key securely here.")
        }
        let config = ProviderAccountConfig(accountId: UUID().uuidString.lowercased(), label: "", probeConfig: entry.values, madeBy: .form)
        let lineupId = config.toProviderAccount(providerId: id).id
        do {
            try keep(entry.secrets, for: lineupId)
        } catch {
            throw UsageError.executionFailed("ClaudeBar couldn't keep this key securely. The account wasn't added.")
        }
        guard let account = add(config) else {
            for name in entry.secrets.keys { vault?.delete(name, provider: lineupId) }
            throw UsageError.executionFailed("This \(name) account can't be added.")
        }
        // Supplying this login's key is an explicit opt-in, even when the
        // product's unconfigured default login starts disabled.
        account.isEnabled = true
        return account
    }

    /// Two logins never share a path setting — the default login's included.
    private func isTaken(_ value: String, by setting: Setting) -> Bool {
        accounts.contains { account in
            guard let other = self.value(of: setting, values: account.isDefault ? [:] : account.values) else { return false }
            return setting.isSamePlace(value, as: other, paths: paths)
        }
    }

    /// *Sign in with browser* — runs the definition's login into a new folder
    /// under `root`, then adds it as *Choose Signed-in Folder* would. A folder
    /// that ends up holding no new login is deleted.
    @discardableResult
    public func signIn(with runner: AccountSignIn = AccountSignIn(), under root: URL = SignedInFolder.signInRoot) async throws -> Account {
        guard let call = running.accounts?.signIn else {
            throw UsageError.executionFailed("\(name) has no sign-in.")
        }
        let folder = SignedInFolder.forSignIn(to: id, under: root)
        try await runner.signIn(call, into: folder.url)
        do {
            return try addAccount(folder)
        } catch {
            folders.delete(folder.url)
            throw error
        }
    }

    private func addAccount(_ folder: SignedInFolder) throws -> Account {
        guard let rule = definition.accounts?.folder else {
            throw UsageError.executionFailed("\(name) has no added accounts.")
        }
        let home = folder.url.resolvingSymlinksInPath().path
        let defaultHome = rule.default.map { URL(fileURLWithPath: DataSources.expandPath($0)).resolvingSymlinksInPath().path }
        guard home != defaultHome else {
            throw UsageError.executionFailed("This is the default \(name) login, which is already listed.")
        }
        let values = rule.values(for: home)
        guard let login = signedIn(with: values.merging([rule.accountId.savedAs: ""]) { _, empty in empty }, rule: rule),
              let accountId = login.accountId, let email = login.email else {
            throw UsageError.executionFailed(rule.notSignedIn ?? "No \(name) login found in this folder.")
        }
        let defaultAccountId = dataSources(for: defaultAccount).lazy.compactMap { $0.value(of: rule.accountId.field) }.first
        let listed = accounts.contains {
            $0.values[rule.accountId.savedAs] == accountId || $0.folder?.url.resolvingSymlinksInPath().path == home
        }
        guard accountId != defaultAccountId, !listed else {
            throw UsageError.executionFailed("This \(name) account is already listed.")
        }
        let config = ProviderAccountConfig(
            accountId: UUID().uuidString.lowercased(), label: "", email: email,
            probeConfig: values.merging([rule.accountId.savedAs: accountId]) { _, id in id },
            madeBy: folder.madeBy
        )
        guard let account = add(config) else {
            throw UsageError.executionFailed("This \(name) login can't be added.")
        }
        return account
    }

    /// Who is signed in with these values: the first data source that looks
    /// up a key, filled with them. A folder whose key does not answer holds
    /// no login, whatever else it holds.
    private func signedIn(with values: [String: String], rule: ProviderDefinition.Accounts.Folder) -> (accountId: String?, email: String?)? {
        guard let source = try? running.dataSources(forAccount: values).first(where: { $0.credential != nil }) else { return nil }
        let live = makeDataSource(source, "\(id).new")
        guard live.hasKey else { return nil }
        return (live.value(of: rule.accountId.field).flatMap { $0.isEmpty ? nil : $0 }, live.value(of: rule.email))
    }

    /// *Rename* — the name the person gives a login. Who it is, its values
    /// and its usage stay; an empty name goes back to the email.
    public func rename(_ account: Account, to name: String) {
        guard accounts.contains(where: { $0 === account }) else { return }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.isDefault {
            settings.setDefaultAccountLabel(label.isEmpty ? nil : label, forProvider: id)
        } else if let saved = settings.accounts(forProvider: id).first(where: { $0.accountId == account.accountId }) {
            settings.updateAccount(saved.named(label), forProvider: id)
        }
        account.label = label
    }

    /// *Move* — puts a login at `index` in the person's order, saved.
    public func move(_ account: Account, to index: Int) {
        guard let from = accounts.firstIndex(where: { $0 === account }) else { return }
        accounts.remove(at: from)
        accounts.insert(account, at: min(max(0, index), accounts.count))
        settings.setAccountOrder(accounts.map(\.accountId), forProvider: id)
    }

    /// *Re-auth* for a login ClaudeBar signed in to: runs the definition's
    /// login again in that login's own folder, then refreshes it — so the
    /// identity rule decides whether the same person came back. A folder the
    /// person chose is theirs to sign in to; ClaudeBar never runs a login there.
    @discardableResult
    public func signInAgain(_ account: Account, with runner: AccountSignIn = AccountSignIn()) async throws -> UsageSnapshot {
        guard let call = running.accounts?.signIn, let folder = account.folder, folder.goesWithAccount else {
            throw UsageError.executionFailed("Sign in again in this folder yourself, then refresh.")
        }
        try await runner.signInAgain(call, in: folder.url)
        return try await refresh(account, .interactive)
    }

    /// More than one enabled login, so each needs telling apart by name.
    public var hasSeveralAccounts: Bool {
        accounts.lazy.filter(\.isEnabled).prefix(2).count > 1
    }

    /// The enabled login with the most left — *switch to work*.
    public var bestAccount: Account? {
        accounts.filter(\.isEnabled).max {
            ($0.snapshot?.lowestQuota?.percentRemaining ?? -.infinity) < ($1.snapshot?.lowestQuota?.percentRemaining ?? -.infinity)
        }
    }

    /// The enabled login that makes the provider's status what it is — the
    /// one the popover names. `nil` while every login is healthy.
    public var worstAccount: Account? {
        let worst = accounts.filter(\.isEnabled).max { $0.status < $1.status }
        return worst.flatMap { $0.status > .healthy ? $0 : nil }
    }

    /// The worst quota health across the enabled logins.
    public var status: QuotaStatus {
        accounts.filter(\.isEnabled).map(\.status).max() ?? .healthy
    }

    // MARK: - Data sources — one choice for every login

    /// The data source in use: the one the person picked, else the default.
    public var activeKind: String {
        if let chosen = settings.dataSourceKind(forProvider: definition.id), definition.dataSource(chosen) != nil {
            return chosen
        }
        return definition.defaultDataSource
    }

    /// Switches the data source. `false` when the provider has no such one.
    @discardableResult
    public func use(_ kind: String) -> Bool {
        guard definition.dataSource(kind) != nil else { return false }
        settings.setDataSourceKind(kind, forProvider: definition.id)
        return true
    }

    /// Whether a data source's fallback is on — a fallback the definition
    /// lets the person turn off (`enabledBySetting`) reads that setting; any
    /// other fallback is always on. `false` when there is no fallback.
    public func isFallbackEnabled(from kind: String) -> Bool {
        guard let fallback = definition.dataSource(kind)?.fallback else { return false }
        guard let setting = fallback.enabledBySetting else { return true }
        return settings.isOn(setting, forProvider: definition.id) != false
    }

    /// Turns a switchable fallback on or off; does nothing for one that isn't.
    public func setFallbackEnabled(_ on: Bool, from kind: String) {
        guard let setting = definition.dataSource(kind)?.fallback?.enabledBySetting else { return }
        settings.setOn(on, setting, forProvider: definition.id)
    }

    /// Whether a data source's key lookup finds a key for a login — what a
    /// config card shows as *credentials found*. The default login unless named.
    public func hasKey(for kind: String, account: Account? = nil) -> Bool {
        dataSource(kind, for: account ?? defaultAccount)?.hasKey ?? false
    }

    /// The live data sources a login runs.
    public func dataSources(for account: Account) -> [DataSource] {
        bound[account.id] ?? []
    }

    /// A data source that serves cached usage sets how often the background
    /// may ask (Claude's API: 15 minutes, #204).
    public var backgroundRefreshFloor: Duration? {
        definition.dataSource(activeKind)?.cache.map { .seconds($0.ttl) }
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
        let task = Task { try await run(account, from: active, kind) }
        refreshTasks[account.id] = task
        defer { refreshTasks[account.id] = nil }
        let usage = try await task.value
        if kind == .interactive, active.definition.verifyBeforeBackground {
            markVerified()
        }
        return usage
    }

    /// *Test Connection* — the active data source looks up the key and
    /// fetches for a login (the default unless named), stopping BEFORE
    /// mapping: what came back, or which step failed. An explicit test checks
    /// a CLI session the way an explicit refresh does (#216).
    public func testConnection(_ account: Account? = nil) async -> Result<Response, DataSourceError> {
        let account = account ?? defaultAccount
        guard let active = dataSource(activeKind, for: account) else {
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

    // MARK: - Private

    private func dataSource(_ kind: String, for account: Account) -> DataSource? {
        dataSources(for: account).first { $0.kind == kind }
    }

    /// Where a login's refresh starts: the active data source — or, when the
    /// login's patch left it out, the next one along its fallback chain.
    private func startingDataSource(for account: Account) -> DataSource? {
        var kind: String? = activeKind
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

    /// An added login is checked by being added; the default login once an
    /// explicit refresh succeeds, remembered as `<id>.verifiedAtLeastOnce`.
    private func isVerified(_ account: Account) -> Bool {
        !account.isDefault || settings.isOn("verifiedAtLeastOnce", forProvider: definition.id) == true
    }

    private func markVerified() {
        guard settings.isOn("verifiedAtLeastOnce", forProvider: definition.id) != true else { return }
        settings.setOn(true, "verifiedAtLeastOnce", forProvider: definition.id)
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
        guard let fallback = source.definition.fallback else { return nil }
        if let setting = fallback.enabledBySetting, settings.isOn(setting, forProvider: definition.id) == false {
            return nil
        }
        return dataSource(fallback.to, for: account)
    }


    static func reason(of error: Error) -> UsageError? {
        (error as? DataSourceError)?.reason ?? (error as? UsageError)
    }
}
