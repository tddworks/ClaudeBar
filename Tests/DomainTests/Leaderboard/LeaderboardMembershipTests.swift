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

    @Test func `should keep the person's name, what they share and a key for this Mac when they join`() async throws {
        let membership = try await joined(sharing: ["claude", "codex"])

        #expect(membership.isJoined)
        #expect(membership.username?.value == "tokenwhale")
        #expect(membership.sharing == ["claude", "codex"])
        #expect(membership.isVisible)
        #expect(try SigningKey(rawRepresentation: #require(keys.stored)).publicKey.count == 43)
        #expect(settings.record == LeaderboardRecord(username: "tokenwhale", sharing: ["claude", "codex"], visible: true, lastUpload: nil))
        #expect(!membership.sharesCountry)
    }

    @Test func `should leave the person outside, with no key kept, when their name is taken`() async throws {
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

    @Test func `should refuse to join sharing a provider that keeps no token logs`() async throws {
        let membership = membership()

        await #expect(throws: LeaderboardError.notShareable("gemini")) {
            try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude", "gemini"])
        }
        #expect(!membership.isJoined)
    }

    @Test func `should refuse to join sharing no provider`() async throws {
        await #expect(throws: LeaderboardError.nothingShared) {
            try await membership().join(as: #require(Username("tokenwhale")), sharing: [])
        }
    }

    @Test func `should keep the person joined, with their name and what they share, after a relaunch`() async throws {
        _ = try await joined(sharing: ["codex"])

        let restored = membership()

        #expect(restored.isJoined)
        #expect(restored.username?.value == "tokenwhale")
        #expect(restored.sharing == ["codex"])
    }

    @Test func `should not count the person as joined when this Mac's key is gone`() async throws {
        _ = try await joined()
        keys.stored = nil

        #expect(!membership().isJoined)
    }

    // MARK: - Sharing

    @Test func `should remember which providers the person shares after they change them`() async throws {
        let membership = try await joined()

        try membership.share("mistral")
        membership.stopSharing("claude")

        #expect(membership.sharing == ["mistral"])
        #expect(settings.record?.sharing == ["mistral"])
    }

    @Test func `should refuse to share a provider that keeps no token logs after joining`() async throws {
        let membership = try await joined()

        #expect(throws: LeaderboardError.notShareable("gemini")) { try membership.share("gemini") }
        #expect(membership.sharing == ["claude"])
    }

    @Test func `should send only shared providers' days, each one's logins added up`() async throws {
        let membership = try await joined(sharing: ["claude"])
        let days = membership.dailyTokens(from: [
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 100, output: 10)]),
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 1, output: 1, cacheRead: 5)]),
            LoginDays(providerId: "codex", days: [LeaderboardFixtures.stat(day: 4, input: 999)])
        ])

        #expect(days == [DailyTokens(provider: "claude", day: "2026-10-04", input: 101, output: 11, cacheWrite: 0, cacheRead: 5, unsplit: 0)])
    }

    @Test func `should not send days with no tokens`() async throws {
        let membership = try await joined()
        let days = membership.dailyTokens(from: [
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 3), LeaderboardFixtures.stat(day: 4, input: 5)])
        ])

        #expect(days.map(\.day) == ["2026-10-04"])
    }

    @Test func `should send nothing when the person hasn't joined`() {
        let days = membership().dailyTokens(from: [
            LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 5)])
        ])
        #expect(days.isEmpty)
    }

    // MARK: - Visibility and name

    @Test func `should hide the person from the leaderboard once the server agrees`() async throws {
        let membership = try await joined()

        try await membership.setVisible(false)

        #expect(!membership.isVisible)
        #expect(settings.record?.visible == false)
    }

    @Test func `should keep the person visible when the server can't be reached to hide them`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.unreachable)

        await #expect(throws: LeaderboardError.unreachable) { try await membership.setVisible(false) }
        #expect(membership.isVisible)
    }

    @Test func `should keep the person's old name when the new one is taken`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.usernameTaken)

        await #expect(throws: LeaderboardError.usernameTaken) { try await membership.rename(to: #require(Username("whale2"))) }
        #expect(membership.username?.value == "tokenwhale")
    }

    @Test func `should show the person under their new name once they rename`() async throws {
        let membership = try await joined()

        try await membership.rename(to: #require(Username("whale2")))

        #expect(membership.username?.value == "whale2")
        #expect(settings.record?.username == "whale2")
    }

    // MARK: - The globe

    @Test func `should share the person's country once the server agrees`() async throws {
        let membership = try await joined()

        try await membership.setSharesCountry(true)

        #expect(membership.sharesCountry)
        #expect(settings.record?.sharesCountry == true)
    }

    @Test func `should keep the person's country unshared when the server can't be reached`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.unreachable)

        await #expect(throws: LeaderboardError.unreachable) { try await membership.setSharesCountry(true) }
        #expect(!membership.sharesCountry)
    }

    @Test func `should share the person's country at once when they opt in while joining`() async throws {
        let membership = membership()

        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"], sharesCountry: true)

        #expect(membership.sharesCountry)
    }

    @Test func `should show the globe hint to a member who hasn't shared their country, until they dismiss it`() async throws {
        let membership = try await joined()
        #expect(membership.showsGlobeHint)

        membership.dismissGlobeHint()

        #expect(!membership.showsGlobeHint)
        #expect(settings.record?.globeHintDismissed == true)
    }

    @Test func `should stop showing the globe hint once the person shares their country`() async throws {
        let membership = try await joined()

        try await membership.setSharesCountry(true)

        #expect(!membership.showsGlobeHint)
    }

    @Test func `should keep the globe hint dismissed after a relaunch`() async throws {
        let first = try await joined()
        first.dismissGlobeHint()

        #expect(!membership().showsGlobeHint)
    }

    // MARK: - Profile link

    @Test func `should keep the person's profile link once the server agrees`() async throws {
        let membership = try await joined()
        let link = try #require(ProfileLink(platform: .github, handle: "octocat"))

        try await membership.setLink(link)

        #expect(membership.link == link)
        #expect(settings.record?.link == link)
    }

    @Test func `should forget the person's profile link when they remove it`() async throws {
        let membership = try await joined()
        try await membership.setLink(#require(ProfileLink(platform: .x, handle: "jack")))

        try await membership.setLink(nil)

        #expect(membership.link == nil)
        #expect(settings.record?.link == nil)
    }

    @Test func `should keep no profile link when the server refuses it`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).update(.any, as: .any).willThrow(LeaderboardError.rejected("That isn't a github handle."))

        await #expect(throws: LeaderboardError.rejected("That isn't a github handle.")) {
            try await membership.setLink(#require(ProfileLink(platform: .github, handle: "octocat")))
        }
        #expect(membership.link == nil)
    }

    @Test func `should keep a profile link the person adds while joining`() async throws {
        let membership = membership()
        let link = try #require(ProfileLink(platform: .instagram, handle: "boxcee.codes"))

        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"], link: link)

        #expect(membership.link == link)
    }

    @Test func `should keep the person's profile link after a relaunch`() async throws {
        let first = try await joined()
        try await first.setLink(#require(ProfileLink(platform: .github, handle: "octocat")))

        #expect(membership().link?.handle == "octocat")
    }

    // MARK: - Following the server

    /// `/me` as the server answers it, in its own JSON.
    private func answer(_ json: String) throws -> MemberSummary {
        try JSONDecoder().decode(MemberSummary.self, from: Data(json.utf8))
    }

    @Test func `should follow the name, visibility, globe, country and link another device set, on the next read of /me`() async throws {
        let membership = try await joined()
        given(api).me(period: .any, provider: .any, as: .any).willReturn(try answer(
            #"{"username":"whale2","visible":false,"shareCountry":true,"country":"NL","link":{"platform":"github","handle":"octocat"},"standing":null,"days":[]}"#))

        _ = try await membership.summary(period: .sevenDays)

        #expect(membership.isJoined)
        #expect(membership.username?.value == "whale2")
        #expect(!membership.isVisible)
        #expect(membership.sharesCountry)
        #expect(membership.link == ProfileLink(platform: .github, handle: "octocat"))
        #expect(membership.country == "NL")
        #expect(self.membership().username?.value == "whale2")
    }

    @Test func `should keep what a /me answer doesn't say, as a server from before devices answers`() async throws {
        let membership = try await joined()
        try await membership.setSharesCountry(true)
        try await membership.setLink(#require(ProfileLink(platform: .github, handle: "octocat")))
        given(api).me(period: .any, provider: .any, as: .any).willReturn(try answer(#"{"visible":true,"standing":null,"days":[]}"#))

        _ = try await membership.summary(period: .sevenDays)

        #expect(membership.username?.value == "tokenwhale")
        #expect(membership.sharesCountry)
        #expect(membership.link?.handle == "octocat")
    }

    @Test func `should forget the link when /me says there is none`() async throws {
        let membership = try await joined()
        try await membership.setLink(#require(ProfileLink(platform: .github, handle: "octocat")))
        given(api).me(period: .any, provider: .any, as: .any).willReturn(try answer(#"{"visible":true,"link":null,"standing":null,"days":[]}"#))

        _ = try await membership.summary(period: .sevenDays)

        #expect(membership.link == nil)
    }

    @Test func `should keep a change made here over a /me answer that crossed it`() async throws {
        let api = CrossingLeaderboardAPI()
        let membership = LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs,
                                               calendar: LeaderboardFixtures.calendar)
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])

        async let read = membership.summary(period: .sevenDays)
        while await !api.isAsked { await Task.yield() }
        try await membership.setVisible(false)
        await api.answer(MemberSummary(onBoard: nil, days: [], visible: true))
        _ = try await read

        #expect(!membership.isVisible)
    }

    // MARK: - Leaving

    @Test func `should forget this Mac's key and the membership once the server deletes the person`() async throws {
        let membership = try await joined()

        try await membership.leave()

        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `should keep the person joined, key and all, when the server doesn't confirm they left`() async throws {
        let membership = try await joined()
        api.reset([.given])
        given(api).leave(as: .any).willThrow(LeaderboardError.unreachable)

        await #expect(throws: LeaderboardError.unreachable) { try await membership.leave() }
        #expect(membership.isJoined)
        #expect(keys.stored != nil)
    }

    // MARK: - On and off

    @Test func `should be on until the person turns it off`() {
        #expect(membership().isOn)
    }

    @Test func `should keep the person's name, key and what they share when they turn it off`() async throws {
        let membership = try await joined(sharing: ["claude", "codex"])

        membership.turnOff()

        #expect(!membership.isOn)
        #expect(membership.isJoined)
        #expect(membership.username?.value == "tokenwhale")
        #expect(membership.sharing == ["claude", "codex"])
        #expect(keys.stored != nil)
    }

    @Test func `should stay off after a relaunch`() {
        membership().turnOff()

        #expect(!membership().isOn)
    }

    @Test func `should stay off after the person leaves`() async throws {
        let membership = try await joined()
        membership.turnOff()

        try await membership.leave()

        #expect(!membership.isOn)
        #expect(!self.membership().isOn)
    }

    @Test func `should be on again once the person turns it back on`() {
        let membership = membership()
        membership.turnOff()

        membership.turnOn()

        #expect(membership.isOn)
        #expect(self.membership().isOn)
    }
}
