import Foundation
import Observation
import Domain
import Infrastructure

/// The leaderboard as the app runs it: the membership, the uploader, and the
/// hourly timer that keeps the server current. Views read `membership` and
/// `uploader` directly; this only wires them and reads the public board.
@MainActor
@Observable
final class Leaderboard {
    let membership: LeaderboardMembership
    let uploader: LeaderboardUploader
    let boardPage = URL(string: "https://claudebar.tddworks.com/leaderboard/")!
    let globePage = URL(string: "https://claudebar.tddworks.com/leaderboard/#globe-section")!

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let logs: MonitorTokenLogs
    @ObservationIgnored private var timer: Timer?

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

    /// Uploads once soon after launch, then every hour while joined.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.uploader.uploadDue() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.uploader.uploadDue()
        }
    }

    /// Joins, then sends the last thirty days in the background so the first
    /// rank shows without waiting an hour, and the tab switches at once.
    func join(as username: Username, sharing: Set<String>, sharesCountry: Bool = false) async throws {
        try await membership.join(as: username, sharing: sharing, sharesCountry: sharesCountry)
        Task { await uploader.uploadDue() }
    }

    /// Today's days for `providers`, exactly as an upload would send them —
    /// for the join form's preview.
    func preview(sharing providers: Set<String>) async -> [DailyTokens] {
        let today = DateRange.last(1)
        return DailyTokens.summed(await logs.days(in: today), providers: providers)
    }

    func board(in view: BoardView) async throws -> [Standing] {
        try await api.board(in: view)
    }

    func globe() async throws -> GlobeSummary {
        try await api.globe(in: BoardView(period: .thirtyDays))
    }
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
/// history: Claude, Codex and Mistral today.
@MainActor
final class MonitorTokenLogs: TokenLogs {
    private let monitor: QuotaMonitor

    init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    private var logins: [(providerId: String, history: UsageHistory)] {
        monitor.allProviders.compactMap { $0 as? Account }.compactMap { account in
            account.usageHistory.map { (account.provider.id, $0) }
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
