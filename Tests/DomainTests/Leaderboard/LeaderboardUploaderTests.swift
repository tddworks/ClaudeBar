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

    @Test func `the first upload sends the last thirty days`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(membership.lastUpload == now)
        #expect(settings.record?.lastUpload == now)
    }

    @Test func `a later upload resumes from the day of the last one`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23))

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(3), last: now, calendar: calendar))
    }

    @Test func `a Mac asleep for weeks catches up thirty days at most`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(1, month: 8))

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
    }

    @Test func `a failed upload keeps where it was and says why`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        let uploader = uploader(membership)

        await uploader.uploadDue()

        #expect(membership.lastUpload == nil)
        #expect(uploader.lastError == .unreachable)
    }

    @Test func `a good upload clears the last error`() async throws {
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

    @Test func `a membership the server no longer knows is forgotten here`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unauthorized)

        await uploader(membership).uploadDue()

        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `nothing to send still counts as up to date`() async throws {
        let membership = try await joined()

        await uploader(membership).uploadDue()

        #expect(membership.lastUpload == now)
    }

    @Test func `not joined, nothing is read or sent`() async {
        await uploader(membership()).uploadDue()

        #expect(logs.askedFor == nil)
    }
}
