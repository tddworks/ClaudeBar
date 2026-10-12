import AppKit
import Observation
import Domain
import Infrastructure

/// The leaderboard as the app runs it: the membership, the uploader, the
/// checks that keep the server current, and each board as last read. Views
/// read `membership`, `uploader` and `board` directly; this only wires them
/// and keeps the boards for the app run, so they outlive the popover.
@MainActor
@Observable
final class AppLeaderboard {
    /// How the Mac app names itself on every request (`X-Client`).
    static let client = "claudebar-macos/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")"

    let membership: LeaderboardMembership
    let uploader: LeaderboardUploader
    let boardPage = URL(string: "https://claudebar.tddworks.com/leaderboard/")!
    let globePage = URL(string: "https://claudebar.tddworks.com/leaderboard/#globe-section")!
    /// The rank the member is sharing, while *Share my rank* is open over the popover.
    private(set) var sharing: RankCard?
    /// What the popover says once, after the Leaderboard was turned off there.
    private(set) var offNotice: LeaderboardOffNotice?
    /// *Turn off ▾* is open over the popover.
    private(set) var showsTurnOffMenu = false
    /// The board you're looking at; picking another changes it.
    private(set) var board: Board
    /// This Mac asking to be added to a member (design §2a): in memory only,
    /// never while a member. Kept here, not in the view, so closing the
    /// popover doesn't lose the code or stop the wait.
    private(set) var request: DeviceRequest?
    /// Asking the server for a code, before `request` exists.
    private(set) var isAskingForCode = false
    /// Why asking to be added stopped: the code expired, or the server refused.
    private(set) var requestFailure: LeaderboardError?
    /// *Make this Mac its own device* is under way, maybe waiting for another
    /// device to approve the code `membership.ownDeviceRequest` shows.
    private(set) var isBecomingOwnDevice = false
    /// Why the last answer to a copied key didn't take.
    private(set) var copyFailure: LeaderboardError?
    /// Said once after the copied key was answered, until dismissed.
    private(set) var copyAnswered: String?

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let logs: MonitorTokenLogs
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var boards: [Board] = []
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// The ask for a code under way: one cancelled or replaced meanwhile installs nothing.
    @ObservationIgnored private var askingFor: UUID?

    /// The key store and the machine are the Mac's, from the factory.
    init(monitor: QuotaMonitor,
         api: any LeaderboardAPI = Leaderboard.makeAPI(client: AppLeaderboard.client),
         keys: any SigningKeyStore = Leaderboard.makeKeyStore(),
         machine: any MachineIdentity = Leaderboard.makeMachineIdentity(),
         settings: any LeaderboardSettingsRepository = JSONSettingsRepository.shared) {
        let logs = MonitorTokenLogs(monitor: monitor)
        self.api = api
        self.logs = logs
        let membership = LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs, machine: machine)
        self.membership = membership
        uploader = LeaderboardUploader(membership: membership, logs: logs, api: api)
        let sevenDays = Board(period: .sevenDays, api: api, membership: membership)
        board = sevenDays
        boards = [sevenDays]
    }

    /// Uploads once soon after launch, then asks every five minutes and on
    /// wake; the uploader decides whether the hour has passed. A `Timer`'s
    /// clock stops while the Mac sleeps, so it can't keep the hour itself.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.uploader.uploadDue() }
        }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.uploader.uploadDue() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.uploader.uploadDue()
        }
    }

    /// Joins, then sends the last thirty days in the background so the first
    /// rank shows without waiting an hour, and the tab switches at once.
    func join(as username: Username, sharing: Set<String>, sharesCountry: Bool = false, link: ProfileLink? = nil) async throws {
        try await membership.join(as: username, sharing: sharing, sharesCountry: sharesCountry, link: link)
        Task { await uploader.uploadNow() }
    }

    /// The popover's Refresh: uploads now, whatever tab is open. Nothing
    /// happens when not joined.
    func refresh() async {
        await uploader.uploadNow()
    }

    /// Today's days for `providers`, exactly as an upload would send them —
    /// for the join form's preview.
    func preview(sharing providers: Set<String>) async -> [DailyTokens] {
        let today = DateRange.last(1)
        return DailyTokens.summed(await logs.days(in: today), providers: providers)
    }

    // MARK: On and off

    /// Hides the tab and stops uploads; a member stays a member. From the
    /// popover it says so once, with a way back.
    func turnOff(noting: Bool = true) {
        showsTurnOffMenu = false
        offNotice = noting ? (membership.isJoined ? .paused : .hidden) : nil
        membership.turnOff()
    }

    /// Brings the tab back and catches up at once on the days missed.
    func turnOn() {
        offNotice = nil
        membership.turnOn()
        Task { await uploader.uploadNow() }
    }

    func dismissOffNotice() {
        offNotice = nil
    }

    func toggleTurnOffMenu() {
        showsTurnOffMenu.toggle()
    }

    func closeTurnOffMenu() {
        showsTurnOffMenu = false
    }

    /// *Share* on *Your rank*: opens *Share my rank* with this card.
    func share(_ card: RankCard) {
        sharing = card
    }

    func stopSharing() {
        sharing = nil
    }

    /// The same `Board` each time you come back to it, with its last answer.
    func board(period: BoardPeriod, provider: String?) -> Board {
        if let board = boards.first(where: { $0.period == period && $0.provider == provider }) { return board }
        let board = Board(period: period, provider: provider, api: api, membership: membership)
        boards.append(board)
        return board
    }

    /// *Today · 7 days · 30 days* and *All · Claude · …* on the tab.
    func pick(period: BoardPeriod, provider: String?) {
        board = board(period: period, provider: provider)
    }

    func globe() async throws -> GlobeSummary {
        try await api.globe(period: .thirtyDays)
    }

    // MARK: A new device of a member (design §2a)

    /// *Already a member? Add this Mac*: asks for a code, then waits for a
    /// device of the member to approve it, at the server's pace.
    func requestToJoin() async {
        cancelRequest()
        let asking = UUID()
        askingFor = asking
        isAskingForCode = true
        defer { if askingFor == asking { isAskingForCode = false } }
        do {
            let request = try await membership.requestToJoin()
            // Cancelled, or asked again, while the server answered: this code isn't wanted.
            guard askingFor == asking else { return }
            self.request = request
            waiting = Task { [weak self] in
                do {
                    _ = try await request.waitForApproval()
                } catch is CancellationError {
                } catch {
                    // Only the request still shown says why it stopped: one
                    // cancelled or replaced meanwhile says nothing.
                    guard let self, self.request === request else { return }
                    self.requestFailure = error as? LeaderboardError ?? .unreachable
                }
            }
        } catch {
            guard askingFor == asking else { return }
            requestFailure = error as? LeaderboardError ?? .unreachable
        }
    }

    /// The person knows the member the code was approved for: this Mac joins
    /// as their device and sends its last thirty days.
    func joinThroughRequest(sharing: Set<String>) throws {
        guard let request else { throw LeaderboardError.notJoined }
        try membership.join(through: request, sharing: sharing)
        self.request = nil
        Task { await uploader.uploadNow() }
    }

    /// The person doesn't know that member: this Mac removes itself from it
    /// and keeps nothing.
    func declineRequest() async throws {
        guard let request else { return }
        try await request.decline()
        cancelRequest()
    }

    /// *Cancel* or *Back to joining*: stops asking, and forgets the code.
    func cancelRequest() {
        askingFor = nil
        isAskingForCode = false
        request?.stopWaiting()
        waiting?.cancel()
        waiting = nil
        request = nil
        requestFailure = nil
    }

    // MARK: A key copied from another Mac (design §2a)

    /// *Make this Mac its own device*. A copied key in its first week can't
    /// approve the new one: the code then shows for another device of the
    /// member, and this waits for that approval. Uploads once it's done.
    func becomeOwnDevice() {
        guard !isBecomingOwnDevice else { return }
        isBecomingOwnDevice = true
        copyFailure = nil
        let resumesFrom = membership.lastUpload
        Task { @MainActor in
            defer { isBecomingOwnDevice = false }
            do {
                do {
                    try await membership.becomeOwnDevice()
                } catch LeaderboardError.deviceTooNew where membership.ownDeviceRequest != nil {
                    try await membership.becomeOwnDevice()
                }
                copyAnswered = "This Mac is its own device now."
                    + (resumesFrom.map { " It uploads from \($0.formatted(.dateTime.month(.abbreviated).day())), where the other Mac left off." } ?? "")
                await uploader.uploadNow()
            } catch LeaderboardError.notOffered where !membership.holdsCopiedKey {
                // *Keep the key here* was chosen meanwhile: that answer stands.
            } catch {
                copyFailure = error as? LeaderboardError ?? .unreachable
            }
        }
    }

    /// *Keep the key here*: goes on with the key, and uploads at once.
    func keepKeyHere() {
        do {
            try membership.keepKeyHere()
            copyFailure = nil
            copyAnswered = "This Mac keeps the key. If the other Mac is still in use, the two will overwrite each other's days."
            Task { await uploader.uploadNow() }
        } catch {
            copyFailure = error as? LeaderboardError ?? .unreachable
        }
    }

    func dismissCopyAnswered() {
        copyAnswered = nil
    }
}

/// What the popover says after the Leaderboard was turned off in it.
enum LeaderboardOffNotice {
    /// Not joined: only the tab went away.
    case hidden
    /// Joined: uploads stopped too; the membership stays.
    case paused

    var text: String {
        switch self {
        case .hidden: "Leaderboard hidden. Turn it back on in Settings → Leaderboard."
        case .paused: "Leaderboard paused and hidden. Nothing uploads; your name and days stay. Turn it back on in Settings → Leaderboard."
        }
    }
}

/// Your username as the popover prints it: `@itshan`, or `@i•••` when hidden.
func leaderboardName(_ username: String, hidden: Bool) -> String {
    hidden ? "@\(username.prefix(1))•••" : "@\(username)"
}

/// A two-letter country as people read it, "🇳🇱 Netherlands", or `🌍 ••` when
/// *hide my globe country* is on.
func leaderboardCountryLabel(_ code: String, hidden: Bool) -> String {
    hidden ? "🌍 ••" : leaderboardCountryLabel(code)
}

/// A two-letter country as people read it: its flag and its name, "🇳🇱 Netherlands".
func leaderboardCountryLabel(_ code: String) -> String {
    let flag = String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
    let name = Locale.current.localizedString(forRegionCode: code) ?? code
    return "\(flag) \(name)"
}

/// This Mac's token logs, from every login whose provider reads usage
/// history: Claude, Codex, Mistral and Oh My Pi today.
@MainActor
final class MonitorTokenLogs: TokenLogs {
    private let monitor: QuotaMonitor

    init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    private var logins: [(providerId: String, history: UsageHistory)] {
        monitor.logins.compactMap { account in
            account.usageHistory.map { (account.providerId, $0) }
        }
    }

    var providersWithLogs: Set<String> { Set(logins.map(\.providerId)) }

    func days(in range: DateRange) async -> [LoginDays] {
        var result: [LoginDays] = []
        for login in logins {
            result.append(LoginDays(providerId: login.providerId, days: await login.history.days(in: range).stats))
        }
        return result
    }
}
