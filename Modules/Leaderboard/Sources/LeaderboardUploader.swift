import DataSources
import Foundation
import Observation
import Diagnostics
import Quotas

/// Sends the shared days to the server. The first upload sends the last
/// thirty days; each later one reads all thirty and sends from the day of the
/// last good upload, so a missed hour or a Mac asleep for days heals itself,
/// with each earlier day that grew past what the server took from this
/// device (design §2a). Re-sending a day replaces it on the server, never
/// adds, so an hour that would send only what the last upload sent stays
/// home. A day the server refused alone is sent again with each upload until
/// it is taken or thirty days old.
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

        /// Whether the server already holds all `upload` would send, as this
        /// upload left it: the same key, on the same day, each day as sent.
        func covers(_ upload: Sent) -> Bool {
            key == upload.key && today == upload.today && upload.tokens.allSatisfy(tokens.contains)
        }
    }

    static let window = 30
    static let interval: TimeInterval = 60 * 60

    public init(membership: LeaderboardMembership, logs: any TokenLogs, api: any LeaderboardAPI,
                calendar: Calendar = DataSources.calendar(), now: @escaping () -> Date = Date.init) {
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

    /// One upload: reads the last thirty days, sends the ones due (`Due`),
    /// and records the answer for the membership whose key signed it, and
    /// for no other. An hourly one (`skippingRepeat`) stays home when the
    /// server already holds all it would send.
    private func upload(skippingRepeat: Bool) async {
        guard let credentials = membership.uploadCredentials, !isUploading else {
            // A copied key uploads nothing by design (§2a); the badge says why.
            if membership.holdsCopiedKey { lastError = .keyCopied }
            return
        }
        isUploading = true
        defer { isUploading = false }
        let now = now()
        let window = DateRange.last(Self.window, endingOn: now, calendar: calendar)
        let firstDay = DailyTokens.day(of: window.first, calendar: calendar)
        let retrying = membership.refused.filter { $0.day >= firstDay }
        // What the server holds, as the membership stood when the upload began.
        let due = Due(firstDay: firstDay, since: membership.lastUpload.map { DailyTokens.day(of: $0, calendar: calendar) },
                      taken: membership.sent, heldBefore: membership.heldBefore,
                      refused: Set(retrying.map(ProviderDay.init)))
        let days = await logs.days(in: window)
        let tokens = due(membership.dailyTokens(from: days))
        let sent = Sent(key: credentials.key.publicKey, today: DailyTokens.day(of: now, calendar: calendar), tokens: tokens)
        do {
            var refused: [RefusedDay] = []
            // A refused day waiting to be tried again always goes: the server may take it now.
            let held = skippingRepeat && retrying.isEmpty && lastSent?.covers(sent) == true
            if !tokens.isEmpty, !held {
                refused = try await api.upload(tokens, as: credentials)
            }
            guard membership.recordUpload(at: now, sent: tokens, refused: refused, signedBy: credentials.key) else {
                AppLog.network.info("Leaderboard upload answered for a membership this Mac has since left; recorded nothing")
                return
            }
            if !held { lastSent = sent }
            lastError = nil
            for day in refused {
                AppLog.network.info("Leaderboard refused \(day.provider) on \(day.day): \(day.why); sending it again later")
            }
        } catch LeaderboardError.unauthorized {
            guard membership.forgetUnknownMember(signedBy: credentials.key) else { return }
            lastError = nil
            AppLog.network.info("Leaderboard no longer knows this member; forgot the membership here")
        } catch LeaderboardError.removed(let device) {
            guard membership.forgetRemoved(by: device, signedBy: credentials.key) else { return }
            lastError = nil
            AppLog.network.info("Another device of this member removed this one; forgot the membership here")
        } catch {
            lastError = error as? LeaderboardError ?? .unreachable
            AppLog.network.info("Leaderboard upload failed: \(lastError?.localizedDescription ?? "")")
        }
    }

    /// Which of the days read go (design §2a), of the last thirty: every day
    /// from the last upload's on, as read; an earlier one whose total is
    /// larger than the one the server took from this device, or of which it
    /// took none, the whole day, never the difference, and never one read
    /// smaller; a held earlier day only when refused.
    private struct Due {
        let firstDay: String
        /// The day of the last good upload; `nil` before the first.
        let since: String?
        let taken: [ProviderDay: Int]
        let heldBefore: String?
        let refused: Set<ProviderDay>

        /// The days of `tokens` that go, oldest first as read.
        func callAsFunction(_ tokens: [DailyTokens]) -> [DailyTokens] {
            tokens.filter { day in
                guard day.day >= firstDay else { return false }
                guard let since, day.day < since else { return true }
                let key = ProviderDay(day)
                if let heldBefore, day.day < heldBefore { return refused.contains(key) }
                return taken[key].map { day.total > $0 } ?? true
            }
        }
    }
}
