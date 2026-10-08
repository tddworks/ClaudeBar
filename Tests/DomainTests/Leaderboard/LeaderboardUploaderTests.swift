import Foundation
import Mockable
import Testing
@testable import Domain

@MainActor
@Suite
struct LeaderboardUploaderTests {
    private let api = MockLeaderboardAPI.accepting()
    private let keys = InMemorySigningKeyStore()
    private let settings = InMemoryLeaderboardSettings()
    private let logs = FakeTokenLogs()
    private let calendar = LeaderboardFixtures.calendar
    private var now = LeaderboardFixtures.date(4, hour: 15)

    private func membership() -> LeaderboardMembership {
        LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs, calendar: calendar)
    }

    private func uploader(_ membership: LeaderboardMembership) -> LeaderboardUploader {
        let now = now
        return LeaderboardUploader(membership: membership, logs: logs, api: api, calendar: calendar, now: { now })
    }

    private func joined() async throws -> LeaderboardMembership {
        let membership = membership()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        return membership
    }

    @Test func `should send the last thirty days the first time`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(membership.lastUpload == now)
        #expect(settings.record?.lastUpload == now)
    }

    @Test func `should send from the day of the last upload on`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23))

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(3), last: now, calendar: calendar))
    }

    @Test func `should catch up thirty days at most when the Mac slept for weeks`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(1, month: 8))

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
    }

    @Test func `should keep where it was and say why when an upload can't reach the server`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        let uploader = uploader(membership)

        await uploader.uploadDue()

        #expect(membership.lastUpload == nil)
        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should clear the last error once an upload goes through`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        let uploader = uploader(membership)
        await uploader.uploadDue()

        api.reset([.given])
        given(api).upload(.any, as: .any).willReturn([])
        await uploader.uploadDue()

        #expect(uploader.lastError == nil)
        #expect(membership.lastUpload == now)
    }

    @Test func `should forget the membership and this Mac's key when the server no longer knows the person`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unauthorized)

        await uploader(membership).uploadDue()

        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `should count as up to date when there is nothing to send`() async throws {
        let membership = try await joined()

        await uploader(membership).uploadDue()

        #expect(membership.lastUpload == now)
    }

    @Test func `should not upload again within an hour of the last upload`() async throws {
        let membership = try await joined()
        let last = now.addingTimeInterval(-59 * 60)
        membership.recordUpload(at: last)

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == nil)
        #expect(membership.lastUpload == last)
    }

    @Test func `should upload again once the last upload is an hour old`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: now.addingTimeInterval(-60 * 60))

        await uploader(membership).uploadDue()

        #expect(membership.lastUpload == now)
    }

    @Test func `should upload at once when the person asks, even within the hour`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: now.addingTimeInterval(-5 * 60))

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(4), last: now, calendar: calendar))
        #expect(membership.lastUpload == now)
    }

    // MARK: Nothing new to send

    /// One uploader across several asks, its clock moved between them.
    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func uploader(_ membership: LeaderboardMembership, clock: Clock) -> LeaderboardUploader {
        LeaderboardUploader(membership: membership, logs: logs, api: api, calendar: calendar, now: { clock.now })
    }

    /// Joined, one day of Claude tokens sent once, and the server unreachable from then on:
    /// whatever upload follows succeeds only if it stays home.
    private func sentOnce(at start: Date) async throws -> (LeaderboardMembership, LeaderboardUploader, Clock) {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        let clock = Clock(start)
        let uploader = uploader(membership, clock: clock)
        await uploader.uploadDue()
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        return (membership, uploader, clock)
    }

    @Test func `should count as up to date without asking the server when an hour brought nothing new`() async throws {
        let (membership, uploader, clock) = try await sentOnce(at: now)

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == nil)
        #expect(membership.lastUpload == clock.now)
    }

    @Test func `should send again when the day's tokens grew`() async throws {
        let (_, uploader, clock) = try await sentOnce(at: now)
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 25)])]

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should send the same days again on a new day, so the server's periods move with it`() async throws {
        let (_, uploader, clock) = try await sentOnce(at: LeaderboardFixtures.date(4, hour: 23))

        clock.now = LeaderboardFixtures.date(5, hour: 0).addingTimeInterval(5 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should always send when the person asks, even with nothing new`() async throws {
        let (_, uploader, clock) = try await sentOnce(at: now)

        clock.now = now.addingTimeInterval(5 * 60)
        await uploader.uploadNow()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should send everything after joining again, though the days are the same`() async throws {
        let (membership, uploader, clock) = try await sentOnce(at: now)
        given(api).leave(as: .any).willReturn(())
        given(api).join(username: .any, publicKey: .any).willReturn(())
        try await membership.leave()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should read and send nothing when the person hasn't joined`() async {
        await uploader(membership()).uploadDue()

        #expect(logs.askedFor == nil)
    }

    // MARK: - A refused day

    private static let overCap = RefusedDay(provider: "claude", day: "2026-10-01", reason: "cap")

    /// The days each upload sent, kept from whatever thread the mock answers on.
    private final class SentDays: @unchecked Sendable {
        private let lock = NSLock()
        private var uploads: [[DailyTokens]] = []

        func append(_ days: [DailyTokens]) { lock.withLock { uploads.append(days) } }
        var first: [DailyTokens]? { lock.withLock { uploads.first } }
    }

    /// Answers `refused` to every upload, and keeps the days each one sent. The answer is
    /// `@Sendable`: the mock calls it off the main actor this suite runs on.
    private func refusing(_ refused: [RefusedDay]) -> SentDays {
        let sent = SentDays()
        api.reset([.given])
        given(api).upload(.any, as: .any).willProduce { @Sendable days, _ in
            sent.append(days)
            return refused
        }
        return sent
    }

    @Test func `should keep a refused day and still send the others, moving on as for a good upload`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 10),
                                                                LeaderboardFixtures.stat(day: 4, input: 10)])]
        let sent = refusing([Self.overCap])
        let uploader = uploader(membership)

        await uploader.uploadDue()

        #expect(sent.first?.map(\.day) == ["2026-10-01", "2026-10-04"])
        #expect(membership.lastUpload == now)
        #expect(membership.refused == [Self.overCap])
        #expect(settings.record?.refused == [Self.overCap])
        #expect(uploader.lastError == nil)
    }

    @Test func `should send a refused day again on the hour, though nothing else is new`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 10),
                                                                LeaderboardFixtures.stat(day: 4, input: 10)])]
        _ = refusing([Self.overCap])
        let clock = Clock(now)
        let uploader = uploader(membership, clock: clock)
        await uploader.uploadDue()
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
        #expect(membership.refused == [Self.overCap])
    }

    @Test func `should send a refused day again with the next upload, and none of the days in between`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), refused: [Self.overCap])
        logs.logins = [LoginDays(providerId: "claude", days: (1...4).map { LeaderboardFixtures.stat(day: $0, input: 10) })]
        let sent = refusing([])

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(1), last: now, calendar: calendar))
        #expect(sent.first?.map(\.day) == ["2026-10-01", "2026-10-03", "2026-10-04"])
        #expect(membership.refused.isEmpty)
    }

    @Test func `should stop sending a refused day once it is more than thirty days old`() async throws {
        let membership = try await joined()
        let tooOld = RefusedDay(provider: "claude", day: "2026-09-01", reason: "cap")
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), refused: [tooOld])
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, month: 9, input: 10),
                                                                LeaderboardFixtures.stat(day: 4, input: 10)])]
        let sent = refusing([])

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(3), last: now, calendar: calendar))
        #expect(sent.first?.map(\.day) == ["2026-10-04"])
        #expect(membership.refused.isEmpty)
    }

    @Test(arguments: [LeaderboardError.unreachable, .rejected("The leaderboard answered with something unreadable.")])
    func `should keep a refused day to send again when an upload fails, unreachable or unreadable`(failure: LeaderboardError) async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), refused: [Self.overCap])
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(failure)

        await uploader(membership).uploadNow()

        #expect(membership.refused == [Self.overCap])
        #expect(settings.record?.refused == [Self.overCap])
        #expect(membership.lastUpload == LeaderboardFixtures.date(3, hour: 23))
    }

    // MARK: - On and off

    @Test func `should read and send nothing, and keep where it stopped, while the Leaderboard is off`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(2))
        membership.turnOff()

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == nil)
        #expect(membership.lastUpload == LeaderboardFixtures.date(2))
    }

    @Test func `should catch up from where it stopped once the Leaderboard is back on`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(2))
        membership.turnOff()
        await uploader(membership).uploadDue()

        membership.turnOn()
        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(2), last: now, calendar: calendar))
        #expect(membership.lastUpload == now)
    }
}
