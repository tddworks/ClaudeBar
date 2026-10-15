import Foundation
import Observation
import Quotas

/// *Rest when spent* — the opt-in policy that rests a login whose longest
/// watched quota is spent: out of every judgement until that quota's window
/// ends, then watched again, on its own. The app's hold, never the person's
/// pause; off until the person ticks a login. Kept in the provider's own
/// settings.
@MainActor
@Observable
public final class Rest {
    private static let onKey = "restWhenSpent"
    private static let skipKey = "restWhenSpentSkip"

    @ObservationIgnored private let providerId: String
    @ObservationIgnored private let accounts: Accounts
    @ObservationIgnored private let settings: any ProviderSettingsRepository

    public var isOn: Bool {
        didSet {
            settings.setOn(isOn, Self.onKey, forProvider: providerId)
            // The app's fact follows the app's policy; the exemptions stay.
            if !isOn { accounts.forEach { $0.restingUntil = nil } }
        }
    }

    /// The logins the person woke — never rested again while exempt.
    private var exempt: Set<String>

    init(providerId: String, accounts: Accounts, settings: any ProviderSettingsRepository) {
        self.providerId = providerId
        self.accounts = accounts
        self.settings = settings
        self.isOn = settings.isOn(Self.onKey, forProvider: providerId) ?? false
        self.exempt = Set((settings.value(Self.skipKey, forProvider: providerId) ?? "")
            .split(separator: ",").map(String.init))
    }

    /// Whether `account` may be rested when its longest quota is spent.
    public func mayRest(_ account: Account) -> Bool {
        isOn && !exempt.contains(account.accountId)
    }

    /// *Rest When Spent* — allowing `account` turns the policy on; refusing
    /// it exempts that login alone.
    public func setMayRest(_ allowed: Bool, _ account: Account) {
        if allowed {
            isOn = true
            exempt.remove(account.accountId)
        } else {
            exempt.insert(account.accountId)
        }
        settings.setValue(exempt.isEmpty ? nil : exempt.sorted().joined(separator: ","), Self.skipKey, forProvider: providerId)
    }

    /// *Wake* — end the rest now, and leave this login alone.
    public func wake(_ account: Account) {
        setMayRest(false, account)
        account.restingUntil = nil
    }

    /// After a refresh: rests `account` when its longest watched quota is
    /// spent and that quota says when it refills; drops a rest the fresh
    /// answer no longer holds.
    public func review(_ account: Account) {
        guard account.isEnabled, mayRest(account) else { return }
        let hidden = settings.hiddenQuotaKeys(forProvider: providerId)
        if let until = Self.rest(in: account.snapshot, hidden: hidden) {
            account.restingUntil = until
        } else if account.restingUntil != nil {
            account.restingUntil = nil
        }
    }

    /// When the login's longest watched quota ends its window — `nil` when
    /// nothing says the login should rest. The judgement is what the person
    /// sees: hidden quotas out, a balance with no ceiling never judged,
    /// shares only, spent means depleted — and a quota that cannot say when
    /// it refills never rests a login.
    public static func rest(in snapshot: UsageSnapshot?, hidden: Set<String>, now: Date = .now) -> Date? {
        guard let snapshot else { return nil }
        let shares = snapshot.quotas.filter { quota in
            !hidden.contains(quota.quotaType.quotaKey)
                && quota.percentLeft != nil
                && (quota.window?.length ?? 0) > 0
        }
        guard let longest = shares.map({ $0.window?.length ?? 0 }).max(), longest > 0 else { return nil }
        return shares
            .filter { ($0.window?.length ?? 0) == longest }
            .first(where: \.isDepleted)?
            .window?.resetsAt
            .flatMap { $0 > now ? $0 : nil }
    }
}
