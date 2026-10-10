import Foundation
import Quotas
import Observation

/// This Mac's membership of the leaderboard — a name, a key in your pocket,
/// and the providers you agreed to share. It owns what may leave the Mac:
/// only shared providers, and only providers with token logs can be shared.
/// It never holds a ranking; the server owns that, and a `Board` keeps it.
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
    /// Where the globe puts you, when you opted in. A copy that follows `/me`.
    public private(set) var country: String?
    private var globeHintDismissed = false
    /// Where people on the board can find you, when you added it. Not verified.
    public private(set) var link: ProfileLink?
    /// Whether ClaudeBar takes part at all: the tab, and uploads. Off is a
    /// pause, kept on this Mac only: the membership stays as it was.
    public private(set) var isOn = true
    /// Days the server refused, each alone, with why: sent again with each
    /// upload until the server takes them or they are 30 days old.
    public private(set) var refused: [RefusedDay] = []
    /// The member's devices as `/me` last listed them: a copy, like the name.
    public private(set) var devices: [Device] = []
    /// A new device on its way in: the code it shows, then the member a device
    /// of theirs added it to, until the person agrees. `nil` otherwise.
    public private(set) var joining: Joining?
    /// The device that removed this one, once its key was refused for that:
    /// the membership is forgotten, and this says why.
    public private(set) var removedBy: String?
    private var key: SigningKey?
    /// Devices already shown as added, by key: each is shown once.
    private var shownDevices: Set<String> = []
    /// A new device's key and what the server said, while it is joining.
    private var joiningKey: SigningKey?
    private var joiningInterval: TimeInterval = 5
    private var approvedSummary: MemberSummary?
    /// Changes made here, counted, so a `/me` answer that crossed one is
    /// not taken over it.
    private var changesMadeHere = 0

    /// Where a new device stands on its way in (design §2a).
    public enum Joining: Sendable, Equatable {
        /// It shows `code` until a device of the member approves it.
        case waiting(code: DeviceCode)
        /// A device of `member` approved it; nothing is sent until the person agrees.
        case approved(member: Username)
    }

    /// A device added less than this long ago can't yet act for the member.
    static let firstWeek: TimeInterval = 7 * 24 * 60 * 60

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let keys: any SigningKeyStore
    @ObservationIgnored private let settings: any LeaderboardSettingsRepository
    @ObservationIgnored private let logs: any TokenLogs
    @ObservationIgnored private let machine: any MachineIdentity
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    public init(api: any LeaderboardAPI, keys: any SigningKeyStore, settings: any LeaderboardSettingsRepository,
                logs: any TokenLogs, machine: any MachineIdentity, calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init) {
        self.api = api
        self.keys = keys
        self.settings = settings
        self.logs = logs
        self.machine = machine
        self.calendar = calendar
        self.now = now
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

    /// What this device is called unless the person types another name: the
    /// machine's model, never its computer name.
    public var suggestedLabel: DeviceLabel { machine.model }

    public func join(as username: Username, sharing providers: Set<String>, sharesCountry: Bool = false,
                     link: ProfileLink? = nil, label: DeviceLabel? = nil) async throws {
        guard !providers.isEmpty else { throw LeaderboardError.nothingShared }
        try requireShareable(providers)
        let key = SigningKey.generate()
        try await api.join(username: username.value, publicKey: key.publicKey, label: (label ?? suggestedLabel).value)
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
        startFresh()
        save()
        if sharesCountry { try? await setSharesCountry(true) }
        if let link { try? await setLink(link) }
    }

    // MARK: - Joining as a new device of a member (design §2a)

    /// *Already a member? Add this Mac*: makes this device's key and asks the
    /// server to add it; answers the code to type on a device the member has.
    public func requestToJoin(label: DeviceLabel? = nil) async throws -> DeviceCode {
        let key = SigningKey.generate()
        let authorization = try await api.requestDevice(publicKey: key.publicKey, label: (label ?? suggestedLabel).value)
        joiningKey = key
        joiningInterval = authorization.interval
        approvedSummary = nil
        joining = .waiting(code: authorization.code)
        return authorization.code
    }

    /// Asks, at the interval the server gave, until a device of the member
    /// approves the code; answers the member it joined. Nothing is kept or
    /// sent until the person agrees (`confirmJoining`): a code that leaked
    /// could have been approved by someone else.
    public func waitForApproval() async throws -> Username {
        guard case .waiting = joining, let key = joiningKey else { throw LeaderboardError.notJoined }
        while true {
            let approval: DeviceApproval
            do {
                approval = try await api.approval(of: key)
            } catch LeaderboardError.codeExpired {
                endJoining()
                throw LeaderboardError.codeExpired
            }
            switch approval {
            case .waiting:
                try await Task.sleep(for: .seconds(joiningInterval))
            case .approved(let summary):
                guard let member = summary.username.flatMap(Username.init) else {
                    throw LeaderboardError.rejected("The leaderboard answered with something unreadable.")
                }
                approvedSummary = summary
                joining = .approved(member: member)
                return member
            }
        }
    }

    /// The person knows the member this device was added to: it joins as that
    /// member, sharing `providers`, with nothing uploaded yet, so its first
    /// upload sends the last thirty days.
    public func confirmJoining(sharing providers: Set<String>) throws {
        guard case .approved(let member) = joining, let key = joiningKey, let summary = approvedSummary else {
            throw LeaderboardError.notJoined
        }
        guard !providers.isEmpty else { throw LeaderboardError.nothingShared }
        try requireShareable(providers)
        keys.save(key.rawRepresentation)
        self.key = key
        username = member
        sharing = providers
        isVisible = true
        lastUpload = nil
        refused = []
        sharesCountry = false
        globeHintDismissed = false
        link = nil
        startFresh()
        follow(summary)
        endJoining()
    }

    /// The person doesn't know the member this device was added to: it removes
    /// itself from that member, and keeps nothing.
    public func declineJoining() async throws {
        guard case .approved(let member) = joining, let key = joiningKey else { throw LeaderboardError.notJoined }
        try await api.removeDevice(key.publicKey, as: MemberCredentials(username: member, key: key))
        endJoining()
    }

    private func endJoining() {
        joining = nil
        joiningKey = nil
        approvedSummary = nil
    }

    /// A membership this device starts: no devices known or shown yet, and no
    /// word of an earlier one's removal.
    private func startFresh() {
        devices = []
        shownDevices = []
        removedBy = nil
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

    /// Another device of the member removed this one: its key is revoked, so
    /// the membership is forgotten here, and `removedBy` says which device did it.
    func forgetRemoved(by label: String) {
        forget()
        removedBy = label
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
        devices = []
        shownDevices = []
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

    /// `/me`, signed: you on one board, and the name and settings this copy follows.
    public func summary(period: BoardPeriod, provider: String? = nil) async throws -> MemberSummary {
        guard let credentials else { throw LeaderboardError.notJoined }
        let changesBefore = changesMadeHere
        let summary = try await api.me(period: period, provider: provider, as: credentials)
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
        if summary.reportsSharesCountry {
            sharesCountry = summary.sharesCountry
            country = summary.country
        }
        if summary.reportsLink { link = summary.link }
        devices = summary.devices
        save()
    }

    // MARK: - Devices (design §2a)

    /// This device as `/me` lists it, once read.
    public var thisDevice: Device? {
        key.flatMap { key in devices.first { $0.publicKey == key.publicKey } }
    }

    /// What approving `code` would add, shown above *Approve* so a code read
    /// out to a stranger isn't approved blind.
    public func pendingDevice(code: DeviceCode) async throws -> PendingDevice {
        guard let credentials else { throw LeaderboardError.notJoined }
        return try await api.pendingDevice(code: code, as: credentials)
    }

    /// Adds the device that shows `code`. This device approved it, so it
    /// isn't shown here as one added since this device last looked.
    public func approve(code: DeviceCode) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        let device = try await api.approveDevice(code: code, as: credentials)
        shownDevices.insert(device.publicKey)
        if !devices.contains(where: { $0.publicKey == device.publicKey }) { devices.append(device) }
        save()
    }

    /// Each device added since this one, in use and not yet shown: shown once,
    /// with *Remove* beside it. A device turned off shows them once it is
    /// turned on, and one in its own first week once `/me` lists the others,
    /// which is when that week ends. Devices the member had before this one
    /// aren't news.
    public var addedDevices: [Device] {
        guard isOn, let me = thisDevice else { return [] }
        return devices.filter {
            !$0.isRemoved && $0.publicKey != me.publicKey && $0.addedAt > me.addedAt && !shownDevices.contains($0.publicKey)
        }
    }

    /// `device` was shown as added, so it isn't again.
    public func markShown(_ device: Device) {
        shownDevices.insert(device.publicKey)
        save()
    }

    /// Whether removing `device` offers *Remove and delete its days* beside
    /// *Remove*: only for another device still in its first week, which a
    /// stranger's device approved by mistake would be.
    public func offersDeletingDays(whenRemoving device: Device) -> Bool {
        device.publicKey != thisDevice?.publicKey && isInFirstWeek(device)
    }

    /// Removes `device`: its key is revoked, and its days stay unless
    /// `deletingDays`, which deletes them once it is removed. If deleting
    /// fails, the device is removed all the same and the error says why.
    /// Removing this device forgets the membership once the server confirmed.
    public func remove(device: Device, deletingDays: Bool = false) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.removeDevice(device.publicKey, as: credentials)
        if device.publicKey == credentials.key.publicKey {
            forget()
            return
        }
        let by = DeviceRef(publicKey: credentials.key.publicKey, label: thisDevice?.label ?? suggestedLabel.value)
        devices = devices.map {
            $0.publicKey == device.publicKey
                ? Device(publicKey: $0.publicKey, label: $0.label, addedAt: $0.addedAt, removedAt: now(), removedBy: by)
                : $0
        }
        changesMadeHere += 1
        if deletingDays {
            try await api.deleteDays(of: device.publicKey, provider: nil, day: nil, as: credentials)
        }
    }

    /// Deletes a removed device's days: all of them, or one provider's, or
    /// one day's. Never a side effect of removing it.
    public func deleteDays(of device: Device, provider: String? = nil, day: String? = nil) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.deleteDays(of: device.publicKey, provider: provider, day: day, as: credentials)
    }

    /// Added less than a week ago, and not the device that joined, which is
    /// never held to a first week: that one is the member's earliest.
    private func isInFirstWeek(_ device: Device) -> Bool {
        let joined = devices.min { $0.addedAt < $1.addedAt }
        return device.publicKey != joined?.publicKey && now().timeIntervalSince(device.addedAt) < Self.firstWeek
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
        shownDevices = Set(record.shownDevices)
    }

    private func save() {
        guard let username else { return }
        settings.saveLeaderboardRecord(LeaderboardRecord(username: username.value, sharing: Array(sharing),
                                                         visible: isVisible, lastUpload: lastUpload,
                                                         sharesCountry: sharesCountry, globeHintDismissed: globeHintDismissed,
                                                         link: link, refused: refused, shownDevices: Array(shownDevices)))
    }
}
