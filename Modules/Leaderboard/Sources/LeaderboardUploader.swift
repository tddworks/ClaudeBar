import Foundation
import Observation
import Diagnostics
import Quotas

/// Sends the shared days to the server. The first upload sends the last
/// thirty days; each later one resumes from the day of the last good upload,
/// so a missed hour or a Mac asleep for days heals itself. Re-sending a day
/// replaces it on the server, never adds, so an hour that would send exactly
/// what the last upload sent stays home. A day the server refused alone is
/// sent again with each upload until it is taken or thirty days old.
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
        let window = DateRange.last(Self.window, endingOn: now, calendar: calendar)
        let firstDay = DailyTokens.day(of: window.first, calendar: calendar)
        let retrying = membership.refused.filter { $0.day >= firstDay }
        let days = await logs.days(in: range(endingOn: now, within: window, retrying: retrying))
        let tokens = due(membership.dailyTokens(from: days), retrying: retrying)
        let sent = Sent(key: credentials.key.publicKey, today: DailyTokens.day(of: now, calendar: calendar), tokens: tokens)
        do {
            var refused: [RefusedDay] = []
            // A refused day waiting to be tried again always goes: the server may take it now.
            if !tokens.isEmpty, !(skippingRepeat && retrying.isEmpty && sent == lastSent) {
                refused = try await api.upload(tokens, as: credentials)
            }
            lastSent = sent
            membership.recordUpload(at: now, refused: refused)
            lastError = nil
            for day in refused {
                AppLog.network.info("Leaderboard refused \(day.provider) on \(day.day): \(day.why); sending it again later")
            }
        } catch LeaderboardError.unauthorized {
            membership.forgetUnknownMember()
            lastError = nil
            AppLog.network.info("Leaderboard no longer knows this member; forgot the membership here")
        } catch LeaderboardError.removed(let label) {
            membership.forgetRemoved(by: label)
            lastError = nil
            AppLog.network.info("Another device of this member removed this one; forgot the membership here")
        } catch {
            lastError = error as? LeaderboardError ?? .unreachable
            AppLog.network.info("Leaderboard upload failed: \(lastError?.localizedDescription ?? "")")
        }
    }

    /// From the day of the last upload, or the earliest refused day if that is
    /// sooner; the last thirty days at most.
    private func range(endingOn now: Date, within window: DateRange, retrying: [RefusedDay]) -> DateRange {
        guard let lastUpload = membership.lastUpload, lastUpload > window.first else { return window }
        let earliestRefused = retrying.compactMap { date(of: $0.day) }.min()
        return DateRange(first: min(lastUpload, earliestRefused ?? lastUpload), last: now, calendar: calendar)
    }

    /// The days from the last upload on, and the refused ones before it; not
    /// the days in between, which the server already took.
    private func due(_ tokens: [DailyTokens], retrying: [RefusedDay]) -> [DailyTokens] {
        guard let lastUpload = membership.lastUpload else { return tokens }
        let since = DailyTokens.day(of: lastUpload, calendar: calendar)
        let refused = Set(retrying.map { "\($0.provider) \($0.day)" })
        return tokens.filter { $0.day >= since || refused.contains("\($0.provider) \($0.day)") }
    }

    /// The start of a `yyyy-MM-dd` day, in this Mac's calendar.
    private func date(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
