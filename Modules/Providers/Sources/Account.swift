import DataSources
import Quotas
import Foundation
import Observation

/// A LOGIN YOU PAY FOR — who it is, its saved values, and what we last saw for
/// it. Two Codex logins are two accounts of one `Provider`: two things to
/// watch (each its own pill and menu-bar entry), one thing to fix.
///
/// It knows only itself (TARGET §2.1): who it is, its values, its
/// pause, what we last saw, and what its definition alone says. It names its
/// product by id and never refers to it — ask the product about a login
/// (`provider.refresh(account)`, `provider.isInLineup(account)`), found
/// through the root (`providers.provider(of: account)`).
@MainActor
@Observable
public final class Account: Identifiable {
    /// Its product, by id — a value, never a reference.
    public let providerId: String
    /// What its product's definition says — data, given at birth.
    @ObservationIgnored let definition: ProviderDefinition
    /// Where its own pause is kept.
    @ObservationIgnored private let settings: any ProviderSettingsRepository
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

    /// The login's own *Pause* — never the product's switch.
    public var isEnabled: Bool {
        didSet {
            if isDefault {
                settings.setOn(isEnabled, Provider.plainLoginKey, forProvider: providerId)
            } else {
                settings.setEnabled(isEnabled, forProvider: id)
            }
        }
    }

    /// *Pause* — stop watching this login, without forgetting it: no refresh,
    /// no status, no alert, and the numbers it last showed (CANONICAL §5).
    public func pause() { isEnabled = false }

    /// *Resume* — watch it again. Its kept numbers are there to be replaced by
    /// the next refresh.
    public func resume() { isEnabled = true }

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
        answeredBy.map { definition.dataSource($0)?.label ?? $0 }
    }

    init(definition: ProviderDefinition, settings: any ProviderSettingsRepository, login: ProviderAccount,
         values: [String: String], madeBy: AccountOrigin? = nil,
         usageHistory: UsageHistory? = nil, guestPasses: GuestPasses? = nil) {
        self.providerId = definition.id
        self.definition = definition
        self.settings = settings
        self.usageHistory = usageHistory
        self.guestPasses = guestPasses
        self.id = login.id
        self.isDefault = login.isDefault
        self.accountId = login.accountId
        self.label = login.label
        self.email = login.email
        self.values = values
        self.madeBy = madeBy
        self.isEnabled = login.isDefault
            ? settings.isOn(Provider.plainLoginKey, forProvider: definition.id) ?? true
            : settings.isEnabled(forProvider: login.id, defaultValue: definition.enabledByDefault)
    }

    /// *NOT SET UP* — no usage yet, and the last refresh found no tool on
    /// this Mac or no sign-in to read with. Waiting for the person, not
    /// failing: the definition's `setup` says what it takes (#198).
    public var needsSetup: Bool {
        guard snapshot == nil, let error = lastError as? UsageError else { return false }
        switch error {
        case .cliNotFound, .authenticationRequired: return true
        default: return false
        }
    }

    public var readsUsage: Bool { usageHistory?.hasUsage == true }

    /// QUOTA health — the worst quota in its usage. A failed fetch is not a
    /// status: it is `lastError`, and the last usage stays.
    public var status: QuotaStatus { snapshot?.overallStatus ?? .healthy }

    /// Where the login lives, for a login added by its folder.
    public var folder: SignedInFolder? {
        guard !isDefault, let rule = definition.accounts?.folder, let path = values[rule.savedAs] else { return nil }
        return SignedInFolder(url: URL(fileURLWithPath: path), madeBy: madeBy ?? .folder)
    }

    /// What its tightest quota has left, in percent — `nil` before a usage.
    public var percentLeft: Double? { snapshot?.lowestQuota?.percentRemaining }

    /// The email the data source reported, else the one it was added with.
    public var accountEmail: String? { snapshot?.accountEmail ?? email }

    /// What it is called: the name the person gave it, else its login's
    /// email, else the product's name.
    public var displayName: String {
        let given = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }
        return accountEmail ?? definition.profile.name
    }

    // MARK: - What its definition says

    /// Its product's face — symbol, colours — as the definition gives it.
    public var look: ProviderLook { definition.profile.look }
    public var cliCommand: String { definition.cli ?? "" }
    public var statusPageURL: URL? { definition.profile.links.status }
    /// *Share Claude Code* — read with the plain login's CLI, so only it has them.
    public let guestPasses: GuestPasses?
    /// What this login used, day by day, from its own logs — `nil` when the
    /// provider offers no usage history, doesn't say where an added login's
    /// logs are, or the login was removed (its history goes with it).
    public internal(set) var usageHistory: UsageHistory?

    // MARK: - Recording a fetch (the provider's)

    /// Records what a fetch brought back, and answers with it.
    ///
    /// `nil` when the login was paused as this fetch landed: nothing is
    /// recorded, the numbers it last showed stay, and the caller is told the
    /// fetch was refused rather than handed data it must not record
    /// (CANONICAL §5).
    func succeed(_ usage: UsageSnapshot, from kind: String) -> UsageSnapshot? {
        guard isEnabled else { return nil }
        snapshot = usage
        lastError = nil
        lastFailedStep = nil
        answeredBy = kind
        return usage
    }

    /// Some of its data sources failed while others answered (`together`):
    /// the usage they gave stays, and the failure shows beside it as fetch
    /// health — never wiping what was seen.
    func noteFailure(_ error: Error) {
        // A fetch that lands while the login is paused records nothing —
        // neither a success nor a failure (CANONICAL §5).
        guard isEnabled else { return }
        if let failure = error as? DataSourceError {
            lastError = failure.reason
            lastFailedStep = failure.step
        } else {
            lastError = error
            lastFailedStep = nil
        }
    }

    /// Records what a failed fetch meant, and answers with the error its
    /// caller should throw.
    ///
    /// A login paused as the fetch landed records nothing and keeps its last
    /// numbers — and answers with the failure that happened, never with the
    /// stale error the login kept before the pause (CANONICAL §5).
    @discardableResult
    func fail(_ error: Error) -> Error {
        guard isEnabled else { return error }
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
        return lastError ?? error
    }
}

// MARK: - A login on the Settings page

public extension Configuration {
    /// What a setting holds for this login.
    func value(of setting: Setting, for account: Account) -> String? {
        value(of: setting, ownValues: account.isDefault ? [:] : account.values)
    }

    /// Whether a value of this setting is saved for this login.
    func hasSaved(_ setting: Setting, for account: Account) -> Bool {
        hasSaved(setting, login: account.id, ownValues: account.isDefault ? nil : account.values)
    }
}
