import Foundation
import Observation
import Diagnostics

/// Sends the shared days to the server. The first upload sends the last
/// thirty days; each later one resumes from the day of the last good upload,
/// so a missed hour or a Mac asleep for days heals itself. Re-sending a day
/// replaces it on the server, never adds, so an hour that would send exactly
/// what the last upload sent stays home.
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
    /// What the last good upload since launch sent, from which key on which day.
    @ObservationIgnored private var lastSent: Sent?

    private struct Sent: Equatable {
        let key: String
        let today: String
        let tokens: [DailyTokens]
    }

    static let window = 30
    static let interval: TimeInterval = 60 * 60

    public init(membership: LeaderboardMembership, logs: any TokenLogs, api: any LeaderboardAPI,
                calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.membership = membership
        self.logs = logs
        self.api = api
        self.calendar = calendar
        self.now = now
    }

    /// Uploads when an hour has passed since the last good upload, by the
    /// wall clock: callers may ask as often as they like, and a Mac that slept
    /// through the hour uploads on the first ask after it wakes. When the hour
    /// brought nothing new for the same day, the server already holds it: it
    /// counts as up to date without asking.
    public func uploadDue() async {
        if let lastUpload = membership.lastUpload, now().timeIntervalSince(lastUpload) < Self.interval { return }
        await upload(skippingRepeat: true)
    }

    /// Uploads at once, hour or not: an upload the person asked for.
    public func uploadNow() async {
        await upload(skippingRepeat: false)
    }

    private func upload(skippingRepeat: Bool) async {
        guard let credentials = membership.uploadCredentials, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        let now = now()
        let days = await logs.days(in: range(endingOn: now))
        let tokens = membership.dailyTokens(from: days)
        let sent = Sent(key: credentials.key.publicKey, today: DailyTokens.day(of: now, calendar: calendar), tokens: tokens)
        do {
            if !tokens.isEmpty, !(skippingRepeat && sent == lastSent) { try await api.upload(tokens, as: credentials) }
            lastSent = sent
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
