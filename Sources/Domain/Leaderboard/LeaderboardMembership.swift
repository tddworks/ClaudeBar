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
    /// Where people on the board can find you, when you added it. Not verified.
    public private(set) var link: ProfileLink?
    /// Whether ClaudeBar takes part at all: the tab, and uploads. Off is a
    /// pause, kept on this Mac only: the membership stays as it was.
    public private(set) var isOn = true
    /// Days the server refused, each alone, with why: sent again with each
    /// upload until the server takes them or they are 30 days old.
    public private(set) var refused: [RefusedDay] = []
    private var key: SigningKey?
    /// Changes made here, counted, so a `/me` answer that crossed one is
    /// not taken over it.
    private var changesMadeHere = 0

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

    /// What an upload is signed with: nothing while not joined or turned
    /// off, so nothing leaves the Mac and `lastUpload` stays where it stopped.
    var uploadCredentials: MemberCredentials? {
        isOn ? credentials : nil
    }

    // MARK: - Joining and leaving

    public func join(as username: Username, sharing providers: Set<String>, sharesCountry: Bool = false,
                     link: ProfileLink? = nil) async throws {
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
        refused = []
        self.sharesCountry = false
        globeHintDismissed = false
        self.link = nil
        save()
        if sharesCountry { try? await setSharesCountry(true) }
        if let link { try? await setLink(link) }
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
        refused = []
        sharesCountry = false
        globeHintDismissed = false
        link = nil
        settings.saveLeaderboardRecord(nil)
    }

    // MARK: - On and off

    /// Hides the Leaderboard and stops uploads. A member stays a member.
    public func turnOff() {
        isOn = false
        settings.setLeaderboardOn(false)
    }

    public func turnOn() {
        isOn = true
        settings.setLeaderboardOn(true)
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

    func recordUpload(at date: Date, refused: [RefusedDay] = []) {
        lastUpload = date
        self.refused = refused
        save()
    }

    // MARK: - Name and visibility

    public func setVisible(_ visible: Bool) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(visible: visible), as: credentials)
        isVisible = visible
        changesMadeHere += 1
        save()
    }

    public func rename(to newName: Username) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(username: newName.value), as: credentials)
        username = newName
        changesMadeHere += 1
        save()
    }

    // MARK: - Profile link

    /// Adds, replaces or — with `nil` — removes your profile link on the board.
    public func setLink(_ newLink: ProfileLink?) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(link: newLink.map { .set($0) } ?? .remove), as: credentials)
        link = newLink
        changesMadeHere += 1
        save()
    }

    // MARK: - The globe

    /// Puts your country on the globe, or takes it off: the server forgets it
    /// at once when you turn this off.
    public func setSharesCountry(_ shares: Bool) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.update(MemberChange(sharesCountry: shares), as: credentials)
        sharesCountry = shares
        changesMadeHere += 1
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
        let changesBefore = changesMadeHere
        let summary = try await api.me(in: view, as: credentials)
        if changesMadeHere == changesBefore { follow(summary) }
        return summary
    }

    /// The member's name and settings live on the server, and another device
    /// may change them: this Mac's copy follows what `/me` says, and keeps
    /// what an answer doesn't say (a server from before devices sends no name).
    private func follow(_ summary: MemberSummary) {
        guard isJoined else { return }
        if let name = summary.username.flatMap(Username.init) { username = name }
        isVisible = summary.visible
        if summary.reportsSharesCountry { sharesCountry = summary.sharesCountry }
        if summary.reportsLink { link = summary.link }
        save()
    }

    // MARK: - Private

    private func requireShareable(_ providers: Set<String>) throws {
        if let missing = providers.subtracting(logs.providersWithLogs).sorted().first {
            throw LeaderboardError.notShareable(missing)
        }
    }

    private func restore() {
        isOn = settings.isLeaderboardOn()
        guard let record = settings.leaderboardRecord(), let name = Username(record.username),
              let raw = keys.load(), let key = try? SigningKey(rawRepresentation: raw) else { return }
        self.key = key
        username = name
        sharing = Set(record.sharing)
        isVisible = record.visible
        lastUpload = record.lastUpload
        sharesCountry = record.sharesCountry
        globeHintDismissed = record.globeHintDismissed
        link = record.link
        refused = record.refused
    }

    private func save() {
        guard let username else { return }
        settings.saveLeaderboardRecord(LeaderboardRecord(username: username.value, sharing: Array(sharing),
                                                         visible: isVisible, lastUpload: lastUpload,
                                                         sharesCountry: sharesCountry, globeHintDismissed: globeHintDismissed,
                                                         link: link, refused: refused))
    }
}
