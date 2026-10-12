import Crypto
import Diagnostics
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
    public private(set) var devices = MemberDevices()
    /// The device that removed this one, once its key was refused for that:
    /// the membership is forgotten, and this says why.
    public private(set) var removedBy: DeviceRef?
    private var key: SigningKey?
    /// Devices already shown as added, by key: each is shown once.
    private var shownDevices: Set<DeviceKey> = []
    /// Which machine made the key: its hardware UUID hashed with the key's
    /// public half (design §2a). `nil` for a key from before this, or made
    /// where the UUID can't be read.
    private var machineHash: String?
    /// The key beside the hash came from another machine (design §2a): found
    /// at launch, when the hash isn't this machine's. Nothing uploads under
    /// it until the member answers: `becomeOwnDevice()` or `keepKeyHere()`.
    public private(set) var holdsCopiedKey = false
    /// This machine asking to be its own device while the copied key, in its
    /// first week, can't approve it: shows the code for another device of
    /// the member to approve, and `becomeOwnDevice()` finishes once it is.
    public private(set) var ownDeviceRequest: DeviceRequest?
    /// Changes made here, counted, so a `/me` answer that crossed one is
    /// not taken over it.
    private var changesMadeHere = 0
    /// A direct join waiting for the server. No other join starts until it
    /// ends, so none replaces, or deletes, the key it kept.
    @ObservationIgnored private var isJoining = false

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

    /// What an upload is signed with: nothing while not joined, turned off
    /// or holding a copied key, so nothing leaves the Mac and `lastUpload`
    /// stays where it stopped.
    var uploadCredentials: MemberCredentials? {
        isOn && !holdsCopiedKey ? credentials : nil
    }

    // MARK: - Joining and leaving

    /// What this device is called unless the person types another name: the
    /// machine's model, never its computer name.
    public var suggestedLabel: DeviceLabel { machine.model }

    /// Joins as `username`. The key is kept before the server hears of it, so
    /// a device whose key store refuses it never becomes a member it can't
    /// sign as after a relaunch; a join the server refuses keeps no key.
    public func join(as username: Username, sharing providers: Set<String>, sharesCountry: Bool = false,
                     link: ProfileLink? = nil, label: DeviceLabel? = nil) async throws {
        guard !isJoined, !isJoining else { throw LeaderboardError.alreadyJoined }
        guard !providers.isEmpty else { throw LeaderboardError.nothingShared }
        try requireShareable(providers)
        isJoining = true
        defer { isJoining = false }
        let key = SigningKey.generate()
        try keep(key)
        do {
            try await api.join(username: username.value, publicKey: key.publicKey, label: (label ?? suggestedLabel).value)
        } catch {
            keys.delete()
            throw error
        }
        self.key = key
        machineHash = machineHash(for: key)
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
    /// server to add it; answers the request, with the code to type on a
    /// device the member has. Never while this Mac is a member.
    public func requestToJoin(label: DeviceLabel? = nil) async throws -> DeviceRequest {
        guard !isJoined else { throw LeaderboardError.alreadyJoined }
        let key = SigningKey.generate()
        let authorization = try await api.requestDevice(publicKey: key.publicKey, label: (label ?? suggestedLabel).value)
        return DeviceRequest(code: authorization.code, key: key, interval: authorization.interval, api: api)
    }

    /// The person knows the member `request` was added to: this Mac joins as
    /// that member's device, sharing `providers`, with nothing uploaded yet,
    /// so its first upload sends the last thirty days. The key is kept first:
    /// if this Mac can't keep it, the request stays approved to try again.
    public func join(through request: DeviceRequest, sharing providers: Set<String>) throws {
        guard !isJoined, !isJoining else { throw LeaderboardError.alreadyJoined }
        guard !providers.isEmpty else { throw LeaderboardError.nothingShared }
        try requireShareable(providers)
        guard case .approved = request.stage else { throw LeaderboardError.notJoined }
        try keep(request.key)
        let approval = try request.handOver()
        key = approval.key
        machineHash = machineHash(for: approval.key)
        username = approval.member
        sharing = providers
        isVisible = true
        lastUpload = nil
        refused = []
        sharesCountry = false
        globeHintDismissed = false
        link = nil
        startFresh()
        follow(approval.summary)
    }

    /// Saves this device's key and reads it back: a device joins only with a
    /// key it will still have after a relaunch (design §4).
    private func keep(_ key: SigningKey) throws {
        keys.save(key.rawRepresentation)
        guard keys.load() == key.rawRepresentation else {
            keys.delete()
            throw LeaderboardError.keyNotKept
        }
    }

    /// A membership this device starts: no devices known or shown yet, and no
    /// word of an earlier one's removal.
    private func startFresh() {
        devices = MemberDevices()
        shownDevices = []
        removedBy = nil
    }

    // MARK: - A key copied from another machine (design §2a)

    /// *Keep the key here*: the other machine is gone, or this is the same
    /// one after a repair. Records this machine beside the key and changes
    /// nothing else. Chosen while the other machine is still in use, it
    /// leaves two machines on one key, which replace each other's days.
    public func keepKeyHere() throws {
        guard holdsCopiedKey, let key else { throw LeaderboardError.notOffered }
        machineHash = machineHash(for: key)
        holdsCopiedKey = false
        ownDeviceRequest = nil
        save()
    }

    /// *Make this machine its own device*: a new key, added as a device of
    /// the member, which the copied key, still signing, approves, as *Add a
    /// device* does. The copied key, its hash and its refused days are
    /// forgotten, which are the other machine's to retry; `lastUpload` is
    /// kept, so the first upload under the new key starts the day the other
    /// machine's left off, not thirty days back. The new key is an added
    /// device, held to its first week.
    ///
    /// A copied key in its first week can't approve: the request then stays
    /// in `ownDeviceRequest`, showing the code for another device of the
    /// member to approve, and calling this again finishes it. That code is on
    /// screen, and one that leaked could be approved by a stranger's device,
    /// which would make this machine the stranger's and send its days there:
    /// an approval is taken only for the member the copied key reads as its
    /// own, and any other is declined, the new key removing itself from
    /// there. A new key this machine can't keep leaves the request approved,
    /// to try again; a code that expired is dropped, for a new one.
    ///
    /// One switch runs at a time: a second ask while one waits for the
    /// server is refused, so two keys are never registered. The person may
    /// answer *Keep the key here* while a switch waits: their answer stands,
    /// and the switch, finding the key no longer a copy or its request no
    /// longer the one asked for, adds nothing, removing from the member a
    /// device it had already added.
    public func becomeOwnDevice() async throws {
        guard holdsCopiedKey, !isSwitching, let credentials else { throw LeaderboardError.notOffered }
        isSwitching = true
        defer { isSwitching = false }
        let request: DeviceRequest
        if let pending = ownDeviceRequest {
            request = pending
        } else {
            let key = SigningKey.generate()
            let authorization = try await api.requestDevice(publicKey: key.publicKey, label: suggestedLabel.value)
            request = DeviceRequest(code: authorization.code, key: key, interval: authorization.interval, api: api)
            guard holdsCopiedKey else { throw LeaderboardError.notOffered }
            ownDeviceRequest = request
            _ = try await api.approveDevice(code: request.code, as: credentials)
        }
        let member: Username
        do {
            member = try await request.waitForApproval()
        } catch LeaderboardError.codeExpired {
            if ownDeviceRequest === request { ownDeviceRequest = nil }
            throw LeaderboardError.codeExpired
        }
        try await requireSwitching(request, approvedBy: member)
        // The member as the copied key reads it now, so a rename on another
        // device doesn't refuse the right approval. Names are unique ignoring case.
        _ = try await summary(period: .sevenDays)
        try await requireSwitching(request, approvedBy: member)
        guard let username, member.value.lowercased() == username.value.lowercased() else {
            ownDeviceRequest = nil
            try await withdraw(request, ours: false)
            throw LeaderboardError.approvedByStranger
        }
        keys.save(request.key.rawRepresentation)
        guard keys.load() == request.key.rawRepresentation else {
            // The copied key goes back, read back as `keep(_:)` does. Not
            // deleted first: a store that refuses writes still holds it, and
            // deleting would leave nothing. A store that keeps neither is
            // logged: this session signs with the copied key, the next may not.
            keys.save(credentials.key.rawRepresentation)
            if keys.load() != credentials.key.rawRepresentation {
                AppLog.credentials.error("Leaderboard key store kept neither the new key nor the copied one; the membership may not survive a relaunch")
            }
            throw LeaderboardError.keyNotKept
        }
        let approval = try request.handOver()
        key = approval.key
        machineHash = machineHash(for: approval.key)
        holdsCopiedKey = false
        ownDeviceRequest = nil
        refused = []
        startFresh()
        follow(approval.summary)
    }

    /// A switch in flight, so a second ask is refused and the person's
    /// *Keep the key here* isn't undone by a switch that finishes after it.
    @ObservationIgnored private var isSwitching = false

    /// Whether `request` is still the switch asked for, after an await: the
    /// key is still a copy and no answer replaced the request. When not, a
    /// device the switch added is removed from the member again, whichever
    /// member `approvedBy` says that is: a stranger's approval overtaken by
    /// *Keep the key here* left the device on the stranger's, not this one.
    private func requireSwitching(_ request: DeviceRequest, approvedBy member: Username? = nil) async throws {
        guard !holdsCopiedKey || ownDeviceRequest !== request else { return }
        let ours = member.map { $0.value.lowercased() == username?.value.lowercased() } ?? true
        try await withdraw(request, ours: ours)
        throw LeaderboardError.notOffered
    }

    /// Removes from the member a device `request` added that this machine
    /// has no use for. A removal the server didn't take is said, not
    /// swallowed: the device stays on that member under a key this machine
    /// doesn't keep, and `ours` says whose member that is.
    private func withdraw(_ request: DeviceRequest, ours: Bool) async throws {
        guard case .approved = request.stage else { return }
        do {
            try await request.decline()
        } catch {
            AppLog.network.error("Leaderboard couldn't remove the device a switch added: \(error.localizedDescription)")
            throw LeaderboardError.deviceLeftBehind(request.key.deviceKey, ours: ours)
        }
    }

    /// Which machine `key` is on: its hardware UUID hashed with the key's
    /// public half, so one machine's two keys don't match and the UUID never
    /// reaches a settings file. `nil` where the UUID can't be read.
    private func machineHash(for key: SigningKey) -> String? {
        guard let uuid = machine.hardwareUUID else { return nil }
        let digest = SHA256.hash(data: Data("\(key.publicKey)\n\(uuid)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
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
    func forgetRemoved(by device: DeviceRef) {
        forget()
        removedBy = device
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
        devices = MemberDevices()
        shownDevices = []
        machineHash = nil
        holdsCopiedKey = false
        ownDeviceRequest = nil
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

    /// Everything the server holds about the member, `/me/export`, as the
    /// server sent it: what Settings' *Export…* saves. Nothing here follows
    /// it; `summary(period:provider:)` is the read this copy follows.
    public func export() async throws -> Data {
        guard let credentials else { throw LeaderboardError.notJoined }
        return try await api.export(as: credentials)
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
        devices = MemberDevices(summary.devices)
        save()
    }

    // MARK: - Devices (design §2a)

    /// This device as `/me` lists it, once read.
    public var thisDevice: Device? {
        key.flatMap { devices.device(withKey: $0.deviceKey) }
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
        devices = devices.adding(device)
        save()
    }

    /// Each device added since this one, in use and not yet shown: shown once,
    /// with *Remove* beside it. A device turned off shows them once it is
    /// turned on, and one in its own first week once `/me` lists the others,
    /// which is when that week ends. Devices the member had before this one
    /// aren't news.
    public var addedDevices: [Device] {
        guard isOn, let me = thisDevice else { return [] }
        return devices.added(since: me).filter { !shownDevices.contains($0.publicKey) }
    }

    /// `device` was shown as added, so it isn't again.
    public func markShown(_ device: Device) {
        shownDevices.insert(device.publicKey)
        save()
    }

    /// How removing `device` may go, as the dialog offers it: *Remove*, and
    /// beside it *Remove and delete its days* only for another device still
    /// in its first week, which a stranger's device approved by mistake would
    /// be. Nothing for a device already removed.
    public func removals(of device: Device) -> [Removal] {
        guard !device.isRemoved else { return [] }
        let isAnother = device.publicKey != thisDevice?.publicKey
        return isAnother && devices.isInFirstWeek(device, at: now()) ? [.keepingItsDays, .deletingItsDays] : [.keepingItsDays]
    }

    /// Removes `device` as `removal` says, one of its `removals(of:)`: its key
    /// is revoked, and its days stay unless `deletingItsDays`, which deletes
    /// them once it is removed. If deleting fails, the device is removed all
    /// the same and the error says why. Removing this device forgets the
    /// membership once the server confirmed.
    public func remove(_ device: Device, _ removal: Removal = .keepingItsDays) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        guard removals(of: device).contains(removal) else { throw LeaderboardError.notOffered }
        try await api.removeDevice(device.publicKey.value, as: credentials)
        if device.publicKey == credentials.key.deviceKey {
            forget()
            return
        }
        let by = DeviceRef(publicKey: credentials.key.deviceKey, label: thisDevice?.label ?? suggestedLabel)
        devices = devices.removing(device, by: by, at: now())
        changesMadeHere += 1
        if removal == .deletingItsDays {
            try await api.deleteDays(of: device.publicKey.value, provider: nil, day: nil, as: credentials)
        }
    }

    /// Deletes a removed device's days: all of them, or one provider's, or
    /// one day's. Never a side effect of removing it.
    public func deleteDays(of device: Device, provider: String? = nil, day: String? = nil) async throws {
        guard let credentials else { throw LeaderboardError.notJoined }
        try await api.deleteDays(of: device.publicKey.value, provider: provider, day: day, as: credentials)
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
        shownDevices = Set(record.shownDevices.map(DeviceKey.init))
        machineHash = record.machine
        checkMachine()
    }

    /// Whether the key is this machine's (design §2a): a hash that isn't this
    /// machine's is a copy, which uploads nothing until answered; a key with
    /// no hash, from before hashes were kept, gets this machine's now, so a
    /// copy made before then goes unnoticed. A machine whose UUID can't be
    /// read keeps what it has and asks nothing.
    private func checkMachine() {
        guard let key, let thisMachine = machineHash(for: key) else { return }
        switch machineHash {
        case nil:
            machineHash = thisMachine
            save()
        case thisMachine:
            break
        default:
            holdsCopiedKey = true
        }
    }

    private func save() {
        guard let username else { return }
        settings.saveLeaderboardRecord(LeaderboardRecord(username: username.value, sharing: Array(sharing),
                                                         visible: isVisible, lastUpload: lastUpload,
                                                         sharesCountry: sharesCountry, globeHintDismissed: globeHintDismissed,
                                                         link: link, refused: refused, shownDevices: shownDevices.map(\.value),
                                                         machine: machineHash))
    }
}
