import DataSources
import Kit
import Foundation
import Observation
import Quotas

/// *The Accounts card* — a provider's logins, in the order the person put
/// them, and what you tell them: add one (by its form, a signed-in folder or
/// signing in), remove, rename, move, sign in again (TARGET §2.1).
///
/// It owns the logins and knows no one above it. What its provider must
/// follow — a login kept or let go — it reports through `onChange`, the one
/// closure the provider gives it: an event going out, never a reference up.
@MainActor
@Observable
public final class Accounts {
    /// What happened to the logins, for the provider to follow.
    enum Change {
        /// A login was kept; `byKey` when the person supplied its key — an
        /// opt-in to the product too.
        case added(Account, byKey: Bool)
        case removed(Account)
    }

    /// The logins, in the person's order — never empty, one the default.
    private(set) var logins: [Account] = []

    @ObservationIgnored private let definition: ProviderDefinition
    @ObservationIgnored private let settings: any MultiAccountSettingsRepository
    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private let folders: any LoginFolders
    @ObservationIgnored private let makeDataSource: (DataSourceDefinition, String) -> DataSource
    @ObservationIgnored private let makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)?
    /// Where what happened goes — given once by the provider.
    @ObservationIgnored private var onChange: (Change) -> Void = { _ in }

    init(definition: ProviderDefinition, settings: any MultiAccountSettingsRepository, configuration: Configuration,
         folders: any LoginFolders, makeDataSource: @escaping (DataSourceDefinition, String) -> DataSource,
         makeUsageHistory: ((UsageLog.Definition, String) -> UsageHistory)?) {
        self.definition = definition
        self.settings = settings
        self.configuration = configuration
        self.folders = folders
        self.makeDataSource = makeDataSource
        self.makeUsageHistory = makeUsageHistory
    }

    /// The logins saved for this provider, made — the plain login first
    /// (with the history and guest passes only it has), then each saved one,
    /// in the saved order.
    func start(plainHistory: UsageHistory?, guestPasses: GuestPasses?,
               onChange: @escaping (Change) -> Void, saved: [ProviderAccountConfig]) {
        let label = settings.defaultAccountLabel(forProvider: id) ?? ""
        logins = [Account(definition: definition, settings: settings, login: ProviderAccount(providerId: id, label: label),
                          values: [:], usageHistory: plainHistory, guestPasses: guestPasses)]
        for config in saved { attach(config) }
        let order = settings.accountOrder(forProvider: id)
        logins = logins.enumerated().sorted { lhs, rhs in
            let (left, right) = (order.firstIndex(of: lhs.element.accountId) ?? order.count + lhs.offset,
                                 order.firstIndex(of: rhs.element.accountId) ?? order.count + rhs.offset)
            return left < right
        }.map(\.element)
        self.onChange = onChange
    }

    private var id: String { definition.id }
    private var name: String { definition.profile.name }

    // MARK: - It answers

    /// The plain login the CLI already uses — found by being the default,
    /// wherever the person moved it.
    public var plain: Account { logins.first(where: \.isDefault)! }

    /// The login a person or a link names: its id, its account id
    /// (`default` for the plain login), its name or its email — any case.
    public func named(_ name: String) -> Account? {
        let wanted = name.lowercased()
        return logins.first { $0.id.lowercased() == wanted || $0.accountId.lowercased() == wanted }
            ?? logins.first { $0.displayName.lowercased() == wanted || $0.accountEmail?.lowercased() == wanted }
    }

    /// More than one enabled login, so each needs telling apart by name.
    public var hasSeveral: Bool {
        logins.lazy.filter(\.isEnabled).prefix(2).count > 1
    }

    /// The enabled login with the most left — *switch to work*.
    public var best: Account? {
        logins.filter(\.isEnabled).max {
            ($0.snapshot?.lowestQuota?.percentRemaining ?? -.infinity) < ($1.snapshot?.lowestQuota?.percentRemaining ?? -.infinity)
        }
    }

    /// The enabled login that makes the provider's status what it is — the
    /// one the popover names. `nil` while every login is healthy.
    public var worst: Account? {
        let worst = logins.filter(\.isEnabled).max { $0.status < $1.status }
        return worst.flatMap { $0.status > .healthy ? $0 : nil }
    }

    /// What *Add Account*'s form asks for: the account settings the active
    /// data source uses.
    public var form: [Setting] {
        definition.accountSettings.filter { $0.isUsed(by: configuration.activeKind) }
    }

    // MARK: - Tell it

    /// A saved login kept beside the default one — what each way of adding
    /// ends in. `nil` when the definition has no added accounts, the login is
    /// already listed, or its values don't fill what the definition needs.
    @discardableResult
    func add(_ config: ProviderAccountConfig, byKey: Bool = false) -> Account? {
        guard let account = attach(config) else { return nil }
        settings.addAccount(config, forProvider: id)
        onChange(.added(account, byKey: byKey))
        return account
    }

    /// *Choose Signed-in Folder* — adds the login a folder holds, read by the
    /// definition's own lookups filled with that folder. Refused when the
    /// folder holds no key, or the login is the default one or already listed.
    @discardableResult
    public func add(signedInAt folder: URL) throws -> Account {
        try add(SignedInFolder(url: folder, madeBy: .folder))
    }

    /// *Add Account* by its form — the login's own account-scope settings.
    /// Each value keeps its setting's rule, a default fills a blank, a path
    /// is never another login's, and a secret is kept in the vault under the
    /// new login's id — read back before the login is kept, so nothing is
    /// half saved. Supplying a key opts the login, and its product, in.
    @discardableResult
    public func add(filling entered: [String: String]) throws -> Account {
        let form = form
        guard !form.isEmpty else { throw UsageError.executionFailed("\(name) has no account form.") }
        var entry = SettingEntry()
        for setting in form {
            let value = setting.value(from: entered[setting.id])
            if let problem = setting.check(value, paths: configuration.paths) { throw UsageError.executionFailed(problem) }
            if isTaken(value, by: setting) {
                throw UsageError.executionFailed("Choose a separate folder for \(setting.label) — another \(name) login uses this one.")
            }
            setting.keep(value, in: &entry, paths: configuration.paths)
        }
        guard entry.secrets.isEmpty || configuration.vault != nil else {
            throw UsageError.executionFailed("ClaudeBar can't keep this key securely here.")
        }
        let config = ProviderAccountConfig(accountId: UUID().uuidString.lowercased(), label: "", probeConfig: entry.values, madeBy: .form)
        let lineupId = config.toProviderAccount(providerId: id).id
        do {
            try configuration.keep(entry.secrets, for: lineupId)
        } catch {
            throw UsageError.executionFailed("ClaudeBar couldn't keep this key securely. The account wasn't added.")
        }
        guard let account = add(config, byKey: true) else {
            for name in entry.secrets.keys { configuration.vault?.delete(name, provider: lineupId) }
            throw UsageError.executionFailed("This \(name) account can't be added.")
        }
        account.isEnabled = true
        return account
    }

    /// *Sign in with browser* — runs the definition's login into a new folder
    /// under `root`, then adds it as *Choose Signed-in Folder* would. A folder
    /// that ends up holding no new login is deleted.
    @discardableResult
    public func signIn(with runner: AccountSignIn = AccountSignIn(), under root: URL = SignedInFolder.signInRoot) async throws -> Account {
        guard let call = configuration.running.accounts?.signIn else {
            throw UsageError.executionFailed("\(name) has no sign-in.")
        }
        let folder = SignedInFolder.forSignIn(to: id, under: root)
        try await runner.signIn(call, into: folder.url)
        do {
            return try add(folder)
        } catch {
            folders.delete(folder.url)
            throw error
        }
    }

    /// *Re-auth* for a login ClaudeBar signed in to: runs the definition's
    /// login again in that login's own folder. Refresh it after, so the
    /// identity rule decides whether the same person came back. A folder the
    /// person chose is theirs to sign in to; ClaudeBar never runs a login there.
    public func signInAgain(_ account: Account, with runner: AccountSignIn = AccountSignIn()) async throws {
        guard let call = configuration.running.accounts?.signIn, let folder = account.folder, folder.goesWithAccount else {
            throw UsageError.executionFailed("Sign in again in this folder yourself, then refresh.")
        }
        try await runner.signInAgain(call, in: folder.url)
    }

    /// *Remove* — forgets the login here and its saved settings, and deletes
    /// the folder only when ClaudeBar made it by signing in. A folder the
    /// person chose is theirs and stays. The default login can't be removed.
    public func remove(_ account: Account) {
        guard !account.isDefault, logins.contains(where: { $0 === account }) else { return }
        if let folder = account.folder, folder.goesWithAccount {
            folders.delete(folder.url)
        }
        // Whatever of the form went to the vault goes with the login.
        for setting in definition.accountSettings {
            configuration.vault?.delete(setting.id, provider: account.id)
        }
        logins.removeAll { $0 === account }
        account.usageHistory = nil
        settings.removeAccount(accountId: account.accountId, forProvider: id)
        onChange(.removed(account))
    }

    /// *Rename* — the name the person gives a login. Who it is, its values
    /// and its usage stay; an empty name goes back to the email.
    public func rename(_ account: Account, to name: String) {
        guard logins.contains(where: { $0 === account }) else { return }
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
        guard let from = logins.firstIndex(where: { $0 === account }) else { return }
        logins.remove(at: from)
        logins.insert(account, at: Swift.min(Swift.max(0, index), logins.count))
        settings.setAccountOrder(logins.map(\.accountId), forProvider: id)
    }

    // MARK: - Private

    /// A saved login made — its values checked against what the definition
    /// needs, its own usage history handed to it.
    @discardableResult
    private func attach(_ config: ProviderAccountConfig) -> Account? {
        let login = config.toProviderAccount(providerId: id)
        guard definition.accounts != nil, !login.isDefault, !logins.contains(where: { $0.id == login.id }) else {
            return nil
        }
        var values = config.probeConfig
        if let field = definition.accounts?.folder?.savedAs, let value = values[field], !value.isEmpty {
            values[field] = configuration.paths.canonical(value)
        }
        for setting in definition.accountSettings {
            if case .path = setting.kind, let value = values[setting.id], !value.isEmpty {
                values[setting.id] = configuration.paths.canonical(value)
            }
        }
        do {
            _ = try configuration.sources(for: values, isDefault: false)
        } catch {
            AppLog.providers.error("\(self.id): can't run account \(login.id): \(error.localizedDescription)")
            return nil
        }
        let history = definition.usageHistory(forAccount: values).flatMap { own in makeUsageHistory?(own, login.id) }
        let account = Account(definition: definition, settings: settings, login: login, values: values,
                              madeBy: config.madeBy, usageHistory: history)
        logins.append(account)
        return account
    }

    /// Two logins never share a path setting — the default login's included.
    private func isTaken(_ value: String, by setting: Setting) -> Bool {
        logins.contains { account in
            guard let other = configuration.value(of: setting, ownValues: account.isDefault ? [:] : account.values) else { return false }
            return setting.isSamePlace(value, as: other, paths: configuration.paths)
        }
    }

    private func add(_ folder: SignedInFolder) throws -> Account {
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
        let listed = logins.contains {
            $0.values[rule.accountId.savedAs] == accountId || $0.folder?.url.resolvingSymlinksInPath().path == home
        }
        guard accountId != plainAccountId(rule: rule), !listed else {
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

    /// Who the plain login is, read the way an added folder's login is.
    private func plainAccountId(rule: ProviderDefinition.Accounts.Folder) -> String? {
        let sources = (try? configuration.sources(for: [:], isDefault: true)) ?? []
        return sources.lazy.map { self.makeDataSource($0, self.id) }.compactMap { $0.value(of: rule.accountId.field) }.first
    }

    /// Who is signed in with these values: the first data source that looks
    /// up a key, filled with them. A folder whose key does not answer holds
    /// no login, whatever else it holds.
    private func signedIn(with values: [String: String], rule: ProviderDefinition.Accounts.Folder) -> (accountId: String?, email: String?)? {
        guard let source = try? configuration.running.dataSources(forAccount: values).first(where: { $0.credential != nil }) else { return nil }
        let live = makeDataSource(source, "\(id).new")
        guard live.hasKey else { return nil }
        return (live.value(of: rule.accountId.field).flatMap { $0.isEmpty ? nil : $0 }, live.value(of: rule.email))
    }
}

// MARK: - Its logins, as a collection

extension Accounts: @MainActor RandomAccessCollection {
    public var startIndex: Int { logins.startIndex }
    public var endIndex: Int { logins.endIndex }
    public subscript(position: Int) -> Account { logins[position] }
}
