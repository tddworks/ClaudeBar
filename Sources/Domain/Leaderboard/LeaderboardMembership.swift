import Foundation
import Quotas
import Observation

/// This Mac's membership of the leaderboard — a name, a key in your pocket,
/// and the providers you agreed to share. It owns what may leave the Mac:
/// only shared providers, and only providers with token logs can be shared.
/// It never holds a ranking; the server owns that.
@MainActor
@Observable
public final class LeaderboardMembership {
    public private(set) var username: Username?
    public private(set) var sharing: Set<String> = []
    public private(set) var isVisible = true
    public private(set) var lastUpload: Date?
    /// Your country is on the globe: kept by the server from where your
    /// requests come from, never sent by this Mac. Off until you opt in.
    public private(set) var sharesCountry = false
    private var globeHintDismissed = false
    private var key: SigningKey?

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let keys: any SigningKeyStore
    @ObservationIgnored private let settings: any LeaderboardSettingsRepository
    @ObservationIgnored private let logs: any TokenLogs
    @ObservationIgnored private let calendar: Calendar

    public init(api: any LeaderboardAPI, keys: any SigningKeyStore, settings: any LeaderboardSettingsRepository,
                logs: any TokenLogs, calendar: Calendar = .current) {
        self.api = api
        self.keys = keys
        self.settings = settings
        self.logs = logs
        self.calendar = calendar
        restore()
    }

    public var isJoined: Bool { credentials != nil }

    /// Providers that can be ticked: those with token logs on this Mac.
    public var shareableProviders: Set<String> { logs.providersWithLogs }

    var credentials: MemberCredentials? {
        guard let username, let key else { return nil }
        return MemberCredentials(username: username, key: key)
    }

    // MARK: - Joining and leaving

    public func join(as username: Username, sharing providers: Set<String>, sharesCountry: Bool = false) async throws {
        guard !providers.isEmpty else { throw LeaderboardError.nothingShared }
        try requireShareable(providers)
        let key = SigningKey.generate()
        try await api.join(username: username.value, publicKey: key.publicKey)
        keys.save(key.rawRepresentation)
        self.key = key
        self.username = username
        sharing = providers
        isVisible = true
        lastUpload = nil
        self.sharesCountry = false
        globeHintDismissed = false
        save()
        if sharesCountry { try? await setSharesCountry(true) }
    }

    /// Deletes the member and every row on the server first; the key is
    /// forgotten only once the server confirmed, or the name would be lost
    /// with the data still there.
    public func leave() async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.leave(as: credentials)
        forget()
    }

    /// The server no longer knows this member (swept a day after joining
    /// with nothing uploaded, or removed): forget it here too, so the join
    /// form shows again instead of a key that will never be accepted.
    func forgetUnknownMember() {
        forget()
    }

    private func forget() {
        keys.delete()
        key = nil
        username = nil
        sharing = []
        isVisible = true
        lastUpload = nil
        sharesCountry = false
        globeHintDismissed = false
        settings.saveLeaderboardRecord(nil)
    }

    // MARK: - What is shared

    public func share(_ provider: String) throws {
        try requireShareable([provider])
        sharing.insert(provider)
        save()
    }

    public func stopSharing(_ provider: String) {
        sharing.remove(provider)
        save()
    }

    /// The days that may leave the Mac: shared providers only, each
    /// provider's logins added up per day, days without tokens left out.
    public func dailyTokens(from logins: [LoginDays]) -> [DailyTokens] {
        guard isJoined else { return [] }
        return DailyTokens.summed(logins, providers: sharing, calendar: calendar)
    }

    func recordUpload(at date: Date) {
        lastUpload = date
        save()
    }

    // MARK: - Name and visibility

    public func setVisible(_ visible: Bool) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(visible: visible), as: credentials)
        isVisible = visible
        save()
    }

    public func rename(to newName: Username) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(username: newName.value), as: credentials)
        username = newName
        save()
    }

    // MARK: - The globe

    /// Puts your country on the globe, or takes it off: the server forgets it
    /// at once when you turn this off.
    public func setSharesCountry(_ shares: Bool) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(sharesCountry: shares), as: credentials)
        sharesCountry = shares
        save()
    }

    /// The one-time *NEW* card that offers the globe, until you opt in or dismiss it.
    public var showsGlobeHint: Bool { isJoined && !sharesCountry && !globeHintDismissed }

    public func dismissGlobeHint() {
        globeHintDismissed = true
        save()
    }

    // MARK: - Reading the board

    public func myStanding(in view: BoardView) async throws -> MemberSummary {
        guard let credentials else { throw LeaderboardError.notJoined }
        return try await api.me(in: view, as: credentials)
    }

    // MARK: - Private

    private func requireShareable(_ providers: Set<String>) throws {
        if let missing = providers.subtracting(logs.providersWithLogs).sorted().first {
            throw LeaderboardError.notShareable(missing)
        }
    }

    private func restore() {
        guard let record = settings.leaderboardRecord(), let name = Username(record.username),
              let raw = keys.load(), let key = try? SigningKey(rawRepresentation: raw) else { return }
        self.key = key
        username = name
        sharing = Set(record.sharing)
        isVisible = record.visible
        lastUpload = record.lastUpload
        sharesCountry = record.sharesCountry
        globeHintDismissed = record.globeHintDismissed
    }

    private func save() {
        guard let username else { return }
        settings.saveLeaderboardRecord(LeaderboardRecord(username: username.value, sharing: Array(sharing),
                                                         visible: isVisible, lastUpload: lastUpload,
                                                         sharesCountry: sharesCountry, globeHintDismissed: globeHintDismissed))
    }
}
