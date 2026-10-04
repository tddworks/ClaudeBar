import Foundation
import Observation
import Diagnostics

/// Sends the shared days to the server. The first upload sends the last
/// thirty days; each later one resumes from the day of the last good upload,
/// so a missed hour or a Mac asleep for days heals itself. Re-sending a day
/// replaces it on the server, never adds.
@MainActor
@Observable
public final class LeaderboardUploader {
    /// Why the last upload failed, until one succeeds.
    public private(set) var lastError: LeaderboardError?
    public private(set) var isUploading = false

    @ObservationIgnored private let membership: LeaderboardMembership
    @ObservationIgnored private let logs: any TokenLogs
    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    static let window = 30

    public init(membership: LeaderboardMembership, logs: any TokenLogs, api: any LeaderboardAPI,
                calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.membership = membership
        self.logs = logs
        self.api = api
        self.calendar = calendar
        self.now = now
    }

    public func uploadDue() async {
        guard let credentials = membership.credentials, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        let now = now()
        let days = await logs.days(in: range(endingOn: now))
        let tokens = membership.dailyTokens(from: days)
        do {
            if !tokens.isEmpty { try await api.upload(tokens, as: credentials) }
            membership.recordUpload(at: now)
            lastError = nil
        } catch LeaderboardError.unauthorized {
            membership.forgetUnknownMember()
            lastError = nil
            AppLog.network.info("Leaderboard no longer knows this member; forgot the membership here")
        } catch {
            lastError = error as? LeaderboardError ?? .unreachable
            AppLog.network.info("Leaderboard upload failed: \(lastError?.localizedDescription ?? "")")
        }
    }

    private func range(endingOn now: Date) -> DateRange {
        let window = DateRange.last(Self.window, endingOn: now, calendar: calendar)
        guard let lastUpload = membership.lastUpload, lastUpload > window.first else { return window }
        return DateRange(first: lastUpload, last: now, calendar: calendar)
    }
}
