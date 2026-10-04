import DataSources
import Quotas
import Foundation
import Observation

/// A LOGIN YOU PAY FOR — who it is, its saved values, and what we last saw for
/// it. Two Codex logins are two accounts of one `Provider`: two things to
/// watch (each its own pill and menu-bar entry), one thing to fix.
///
/// An account has no fetching of its own. It conforms to `AIProvider` only as
/// a shim, forwarding to its provider, so the monitor, the pills and the menu
/// bar keep working until `AIProvider` folds into `Provider`.
@MainActor
@Observable
public final class Account: AIProvider {
    /// The product this login belongs to. Held strongly: the app keeps
    /// accounts, and an account needs its provider to fetch.
    public let provider: Provider
    /// `codex` for the default login, `codex.<account>` for an added one —
    /// the ids every saved setting and menu-bar pin is keyed by.
    public let id: String
    public let isDefault: Bool
    /// The login's own id within the provider — `default` for the default login.
    public let accountId: String
    /// The name the person gave it — empty when they gave none.
    public internal(set) var label: String
    /// What the person gave, or its login file holds.
    public let email: String?
    /// Its account settings — the Codex folder, the login's account id.
    public let values: [String: String]
    /// How it was added — `nil` for the default login and for logins saved
    /// before it was recorded.
    public let madeBy: AccountOrigin?

    public var isEnabled: Bool {
        didSet { provider.settings.setEnabled(isEnabled, forProvider: id) }
    }

    // MARK: - What we last saw

    public internal(set) var isSyncing = false
    public internal(set) var snapshot: UsageSnapshot?
    /// Today's `UsageError`, so every screen that reads one keeps reading one.
    public internal(set) var lastError: Error?
    /// Which step failed last — lookup, fetch or mapping. `nil` after a success.
    public internal(set) var lastFailedStep: DataSourceError.Step?
    /// The kind of the data source that produced `snapshot` — *via RPC*.
    public internal(set) var answeredBy: String?

    /// What Settings calls that data source — *RPC*, *API*, *Terminal*.
    public var answeredByLabel: String? {
        answeredBy.map { provider.definition.dataSource($0)?.label ?? $0 }
    }

    init(provider: Provider, login: ProviderAccount, values: [String: String], madeBy: AccountOrigin? = nil) {
        self.provider = provider
        self.id = login.id
        self.isDefault = login.isDefault
        self.accountId = login.accountId
        self.label = login.label
        self.email = login.email
        self.values = values
        self.madeBy = madeBy
        self.isEnabled = provider.settings.isEnabled(forProvider: login.id, defaultValue: provider.definition.enabledByDefault)
    }

    /// QUOTA health — the worst quota in its usage. A failed fetch is not a
    /// status: it is `lastError`, and the last usage stays.
    public var status: QuotaStatus { snapshot?.overallStatus ?? .healthy }

    /// Where the login lives, for a login added by its folder.
    public var folder: SignedInFolder? {
        guard !isDefault, let rule = provider.definition.accounts?.folder, let path = values[rule.savedAs] else { return nil }
        return SignedInFolder(url: URL(fileURLWithPath: path), madeBy: madeBy ?? .folder)
    }

    /// The email the data source reported, else the one it was added with.
    public var accountEmail: String? { snapshot?.accountEmail ?? email }

    /// What it is called: the name the person gave it, else its login's
    /// email, else the product's name.
    public var displayName: String {
        let given = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }
        return accountEmail ?? provider.name
    }

    // MARK: - AIProvider (forwarded to the provider)

    /// The pill's name: the product's while this is the only login to tell
    /// apart, else the account's own.
    public var name: String { provider.hasSeveralAccounts ? displayName : provider.name }

    public var cliCommand: String { provider.definition.cli ?? "" }
    /// The dashboard for the plan the last usage reported (#328).
    public var dashboardURL: URL? {
        provider.definition.profile.links.dashboard(for: snapshot?.accountTier, settings: provider.settingFills(for: self))
    }
    public var statusPageURL: URL? { provider.definition.profile.links.status }
    public var backgroundRefreshFloor: Duration? { provider.backgroundRefreshFloor }
    /// Guest passes are read with the default login's CLI, so only it has them.
    public var guestPasses: GuestPasses? { isDefault ? provider.guestPasses : nil }
    /// What this login used, day by day, from its own logs — `nil` when the
    /// provider offers no usage history, or doesn't say where an added
    /// login's logs are.
    public var usageHistory: UsageHistory? { provider.usageHistory(for: self) }

    public func isAvailable() async -> Bool {
        await provider.isAvailable(self)
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await provider.refresh(self, .interactive)
    }

    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        try await provider.refresh(self, kind)
    }

    public func hasKey(for kind: String) -> Bool {
        provider.hasKey(for: kind, account: self)
    }

    // MARK: - Recording a fetch (the provider's)

    func succeed(_ usage: UsageSnapshot, from kind: String) -> UsageSnapshot {
        snapshot = usage
        lastError = nil
        lastFailedStep = nil
        answeredBy = kind
        return usage
    }

    func fail(_ error: Error) {
        if let failure = error as? DataSourceError {
            lastError = failure.reason
            lastFailedStep = failure.step
        } else {
            lastError = error
            lastFailedStep = nil
        }
        // An added login that is signed out shows nothing rather than its
        // last usage, which would read as still current.
        if !isDefault, let tag = (lastError as? UsageError)?.tag,
           tag == "authenticationRequired" || tag == "sessionExpired" {
            snapshot = nil
        }
    }
}
