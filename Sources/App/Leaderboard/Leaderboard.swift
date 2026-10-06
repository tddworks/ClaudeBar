import AppKit
import Observation
import Domain
import Infrastructure

/// The leaderboard as the app runs it: the membership, the uploader, and the
/// checks that keep the server current. Views read `membership` and
/// `uploader` directly; this only wires them and reads the public board.
@MainActor
@Observable
final class Leaderboard {
    let membership: LeaderboardMembership
    let uploader: LeaderboardUploader
    let boardPage = URL(string: "https://claudebar.tddworks.com/leaderboard/")!
    let globePage = URL(string: "https://claudebar.tddworks.com/leaderboard/#globe-section")!
    /// The rank the member is sharing, while *Share my rank* is open over the popover.
    private(set) var sharing: RankCard?

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let logs: MonitorTokenLogs
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    init(monitor: QuotaMonitor,
         api: any LeaderboardAPI = LeaderboardHTTPClient(),
         keys: any SigningKeyStore = CredentialSigningKeyStore(),
         settings: any LeaderboardSettingsRepository = JSONSettingsRepository.shared) {
        let logs = MonitorTokenLogs(monitor: monitor)
        self.api = api
        self.logs = logs
        membership = LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs)
        uploader = LeaderboardUploader(membership: membership, logs: logs, api: api)
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

    /// *Share* on *Your rank*: opens *Share my rank* with this card.
    func share(_ card: RankCard) {
        sharing = card
    }

    func stopSharing() {
        sharing = nil
    }

    func board(in view: BoardView) async throws -> [Standing] {
        try await api.board(in: view)
    }

    func globe() async throws -> GlobeSummary {
        try await api.globe(in: BoardView(period: .thirtyDays))
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
            result.append(LoginDays(providerId: login.providerId, days: await login.history.days(in: range)))
        }
        return result
    }
}
