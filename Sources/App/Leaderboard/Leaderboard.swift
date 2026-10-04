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
    let boardPage = URL(string: "https://tddworks.github.io/ClaudeBar/leaderboard/")!

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private var timer: Timer?

    init(monitor: QuotaMonitor,
         api: any LeaderboardAPI = LeaderboardHTTPClient(),
         keys: any SigningKeyStore = CredentialSigningKeyStore(),
         settings: any LeaderboardSettingsRepository = JSONSettingsRepository.shared) {
        let logs = MonitorTokenLogs(monitor: monitor)
        self.api = api
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

    /// Joins, then sends the last thirty days straight away so the first
    /// rank shows without waiting an hour.
    func join(as username: Username, sharing: Set<String>) async throws {
        try await membership.join(as: username, sharing: sharing)
        await uploader.uploadDue()
    }

    func board(in view: BoardView) async throws -> [Standing] {
        try await api.board(in: view)
    }
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
