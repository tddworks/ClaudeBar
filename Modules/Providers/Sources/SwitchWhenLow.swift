import Foundation
import Observation

/// *Switch when low* — the opt-in policy that moves new sessions off a login
/// that is running out: below `below` percent left, to the ticked login with
/// the most left. Off until the person turns it on; every login is ticked
/// until they untick it. Kept in the provider's own settings.
@MainActor
@Observable
public final class SwitchWhenLow {
    private static let onKey = "switchWhenLow"
    private static let belowKey = "switchWhenLowBelow"
    private static let skipKey = "switchWhenLowSkip"

    @ObservationIgnored private let providerId: String
    @ObservationIgnored private let settings: any ProviderSettingsRepository

    public var isOn: Bool {
        didSet { settings.setOn(isOn, Self.onKey, forProvider: providerId) }
    }

    /// The percentage left below which new sessions move.
    public var below: Int {
        didSet { settings.setValue(String(below), Self.belowKey, forProvider: providerId) }
    }

    private var skipped: Set<String>

    init(providerId: String, settings: any ProviderSettingsRepository) {
        self.providerId = providerId
        self.settings = settings
        self.isOn = settings.isOn(Self.onKey, forProvider: providerId) ?? false
        self.below = settings.value(Self.belowKey, forProvider: providerId).flatMap(Int.init) ?? 10
        self.skipped = Set((settings.value(Self.skipKey, forProvider: providerId) ?? "").split(separator: ",").map(String.init))
    }

    /// Whether new sessions may move to `account`.
    public func mayPick(_ account: Account) -> Bool {
        !skipped.contains(account.accountId)
    }

    public func setMayPick(_ allowed: Bool, _ account: Account) {
        if allowed { skipped.remove(account.accountId) } else { skipped.insert(account.accountId) }
        settings.setValue(skipped.isEmpty ? nil : skipped.sorted().joined(separator: ","), Self.skipKey, forProvider: providerId)
    }

    /// Where new sessions should move from `current`, among `logins` — `nil`
    /// when the policy is off, `current` has room, or no ticked login has more left.
    public func next(from current: Account, among logins: [Account]) -> Account? {
        guard isOn, let left = current.percentLeft, left < Double(below) else { return nil }
        return logins
            .filter { $0 !== current && !$0.isPaused && mayPick($0) && ($0.percentLeft ?? -1) > left }
            .max { ($0.percentLeft ?? -1) < ($1.percentLeft ?? -1) }
    }
}
