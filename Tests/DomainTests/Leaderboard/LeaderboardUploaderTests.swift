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
        given(api).upload(.any, as: .any).willReturn(())
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

    @Test func `should read and send nothing when the person hasn't joined`() async {
        await uploader(membership()).uploadDue()

        #expect(logs.askedFor == nil)
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
