import Foundation
import Mockable
import Testing
@testable import Domain

@MainActor
@Suite
struct LeaderboardMembershipTests {
    private let api = MockLeaderboardAPI.accepting()
    private let keys = InMemorySigningKeyStore()
    private let settings = InMemoryLeaderboardSettings()
    private let logs = FakeTokenLogs(providersWithLogs: ["claude", "codex", "mistral"])

    private func membership() -> LeaderboardMembership {
        LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs, calendar: LeaderboardFixtures.calendar)
    }

    private func joined(sharing: Set<String> = ["claude"]) async throws -> LeaderboardMembership {
        let membership = membership()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: sharing)
        return membership
    }

    // MARK: - Joining

    @Test func `joining keeps the name, what is shared, and a key for this Mac`() async throws {
        let membership = try await joined(sharing: ["claude", "codex"])

        #expect(membership.isJoined)
        #expect(membership.username?.value == "tokenwhale")
        #expect(membership.sharing == ["claude", "codex"])
        #expect(membership.isVisible)
        #expect(try SigningKey(rawRepresentation: #require(keys.stored)).publicKey.count == 43)
        #expect(settings.record == LeaderboardRecord(username: "tokenwhale", sharing: ["claude", "codex"], visible: true, lastUpload: nil))
        #expect(!membership.sharesCountry)
    }

    @Test func `a taken name leaves you outside, with no key kept`() async throws {
        api.reset([.given])
        given(api).join(username: .any, publicKey: .any).willThrow(LeaderboardError.usernameTaken)
        let membership = membership()

        await #expect(throws: LeaderboardError.usernameTaken) {
            try await membership.join(as: #require(Username("TokenWhale")), sharing: ["claude"])
        }
        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `a provider without token logs can't be shared, even when joining`() async throws {
        let membership = membership()

        await #expect(throws: LeaderboardError.notShareable("gemini")) {
            try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude", "gemini"])
        }
        #expect(!membership.isJoined)
    }

    @Test func `joining shares at least one provider`() async throws {
        await #expect(throws: LeaderboardError.nothingShared) {
            try await membership().join(as: #require(Username("tokenwhale")), sharing: [])
        }
    }

    @Test func `a membership is restored from settings and its key`() async throws {
        _ = try await joined(sharing: ["codex"])

        let restored = membership()

        #expect(restored.isJoined)
        #expect(restored.username?.value == "tokenwhale")
        #expect(restored.sharing == ["codex"])
    }

    @Test func `a saved membership whose key is gone is not joined`() async throws {
        _ = try await joined()
        keys.stored = nil

        #expect(!membership().isJoined)
    }

    // MARK: - Sharing

    @Test func `sharing another provider is kept`() async throws {
        let membership = try await joined()

        try membership.share("mistral")
        membership.stopSharing("claude")

        #expect(membership.sharing == ["mistral"])
        #expect(settings.record?.sharing == ["mistral"])
    }

    @Test func `a provider without token logs can't be ticked later either`() async throws {
        let membership = try await joined()

        #expect(throws: LeaderboardError.notShareable("gemini")) { try membership.share("gemini") }
        #expect(membership.sharing == ["claude"])
    }

    @Test func `only shared providers' days leave the Mac, each provider's logins added up`() async throws {
        let membership = try await joined(sharing: ["claude"])
        let days = membership.dailyTokens(from: [
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 100, output: 10)]),
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 1, output: 1, cacheRead: 5)]),
            LoginDays(providerId: "codex", days: [LeaderboardFixtures.stat(day: 4, input: 999)])
        ])

        #expect(days == [DailyTokens(provider: "claude", day: "2026-10-04", input: 101, output: 11, cacheWrite: 0, cacheRead: 5, unsplit: 0)])
    }

    @Test func `days with no tokens aren't sent`() async throws {
        let membership = try await joined()
        let days = membership.dailyTokens(from: [
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 3), LeaderboardFixtures.stat(day: 4, input: 5)])
        ])

        #expect(days.map(\.day) == ["2026-10-04"])
    }

    @Test func `not joined, nothing leaves`() {
        let days = membership().dailyTokens(from: [
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 5)])
        ])
        #expect(days.isEmpty)
    }

    // MARK: - Visibility and name

    @Test func `hiding is kept once the server agrees`() async throws {
        let membership = try await joined()

        try await membership.setVisible(false)

        #expect(!membership.isVisible)
        #expect(settings.record?.visible == false)
    }

    @Test func `a refused change changes nothing here`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.unreachable)

        await #expect(throws: LeaderboardError.unreachable) { try await membership.setVisible(false) }
        #expect(membership.isVisible)
    }

    @Test func `a taken new name keeps the old one`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.usernameTaken)

        await #expect(throws: LeaderboardError.usernameTaken) { try await membership.rename(to: #require(Username("whale2"))) }
        #expect(membership.username?.value == "tokenwhale")
    }

    @Test func `renaming moves the membership to the new name`() async throws {
        let membership = try await joined()

        try await membership.rename(to: #require(Username("whale2")))

        #expect(membership.username?.value == "whale2")
        #expect(settings.record?.username == "whale2")
    }

    // MARK: - The globe

    @Test func `the country is shared only once the server agrees`() async throws {
        let membership = try await joined()

        try await membership.setSharesCountry(true)

        #expect(membership.sharesCountry)
        #expect(settings.record?.sharesCountry == true)
    }

    @Test func `a refused opt-in leaves the country unshared`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.unreachable)

        await #expect(throws: LeaderboardError.unreachable) { try await membership.setSharesCountry(true) }
        #expect(!membership.sharesCountry)
    }

    @Test func `joining can opt in to the globe at once`() async throws {
        let membership = membership()

        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"], sharesCountry: true)

        #expect(membership.sharesCountry)
    }

    @Test func `the globe hint shows to members who haven't opted in, until dismissed`() async throws {
        let membership = try await joined()
        #expect(membership.showsGlobeHint)

        membership.dismissGlobeHint()

        #expect(!membership.showsGlobeHint)
        #expect(settings.record?.globeHintDismissed == true)
    }

    @Test func `opting in retires the globe hint`() async throws {
        let membership = try await joined()

        try await membership.setSharesCountry(true)

        #expect(!membership.showsGlobeHint)
    }

    @Test func `the globe hint survives a restart dismissed`() async throws {
        let first = try await joined()
        first.dismissGlobeHint()

        #expect(!membership().showsGlobeHint)
    }

    // MARK: - Leaving

    @Test func `leaving deletes on the server, then forgets the key and the membership`() async throws {
        let membership = try await joined()

        try await membership.leave()

        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `a leave the server didn't confirm keeps you joined, key and all`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).leave(as: .any).willThrow(LeaderboardError.unreachable)

        await #expect(throws: LeaderboardError.unreachable) { try await membership.leave() }
        #expect(membership.isJoined)
        #expect(keys.stored != nil)
    }
}
