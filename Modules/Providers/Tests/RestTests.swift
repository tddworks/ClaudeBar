import Foundation
import Mockable
@testable import Providers
import Quotas
import Testing

/// *Rest when spent* — the opt-in policy that rests a login whose longest
/// watched quota is spent, until that quota's window ends; the app's hold,
/// never the person's pause.
@MainActor
@Suite
struct RestTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - The judgement

    private func snapshot(_ quotas: [UsageQuota]) -> UsageSnapshot {
        UsageSnapshot(providerId: "codex", quotas: quotas, capturedAt: now)
    }

    private func weekly(left: Double, resetsIn: TimeInterval?) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .weekly, providerId: "codex",
                   resetsAt: resetsIn.map { now.addingTimeInterval($0) }, windowDuration: 7 * 24 * 3600)
    }

    private func session(left: Double, resetsIn: TimeInterval?) -> UsageQuota {
        UsageQuota(percentRemaining: left, quotaType: .session, providerId: "codex",
                   resetsAt: resetsIn.map { now.addingTimeInterval($0) }, windowDuration: 5 * 3600)
    }

    @Test
    func `should rest until the longest spent quota refills`() {
        let until = now.addingTimeInterval(7 * 24 * 3600)
        #expect(Rest.rest(in: snapshot([weekly(left: 0, resetsIn: 7 * 24 * 3600), session(left: 0, resetsIn: 5 * 3600)]),
                          hidden: [], now: now) == until)
    }

    @Test
    func `should never rest when the spent quota cannot say when it refills`() {
        #expect(Rest.rest(in: snapshot([weekly(left: 0, resetsIn: nil)]), hidden: [], now: now) == nil)
    }

    @Test
    func `should never rest on a window that has already ended`() {
        #expect(Rest.rest(in: snapshot([weekly(left: 0, resetsIn: -60)]), hidden: [], now: now) == nil)
    }

    @Test
    func `should not rest for a spent session while a longer quota has room`() {
        #expect(Rest.rest(in: snapshot([weekly(left: 50, resetsIn: 7 * 24 * 3600), session(left: 0, resetsIn: 5 * 3600)]),
                          hidden: [], now: now) == nil)
    }

    @Test
    func `should not judge a quota the person hid`() {
        // The weekly is hidden, so the longest window the person sees is the
        // session's — and it has room.
        #expect(Rest.rest(in: snapshot([weekly(left: 0, resetsIn: 7 * 24 * 3600), session(left: 50, resetsIn: 5 * 3600)]),
                          hidden: ["weekly"], now: now) == nil)
    }

    @Test
    func `should never judge a balance with no ceiling`() {
        let balance = UsageQuota(percentRemaining: 100, quotaType: .session, providerId: "codex", dollarRemaining: 12)
        #expect(Rest.rest(in: snapshot([balance]), hidden: [], now: now) == nil)
    }

    // MARK: - The policy on real logins

    /// Both logins refreshed with these windows.
    private func usage(_ stub: StubbedProvider, _ codex: Provider, id: String,
                       primary: Int, secondary: Int, primaryReset: Int? = nil, secondaryReset: Int? = nil) async throws {
        stub.network.reset([.given])
        func window(_ used: Int, _ reset: Int?) -> [String: Any] {
            var value: [String: Any] = ["used_percent": used]
            if let reset { value["reset_after_seconds"] = reset }
            return value
        }
        let body: [String: Any] = ["rate_limit": [
            "primary_window": window(primary, primaryReset),
            "secondary_window": window(secondary, secondaryReset),
        ]]
        let data = try JSONSerialization.data(withJSONObject: body)
        given(stub.network).request(.matching { @Sendable in $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == id })
            .willReturn((data, StubbedProvider.response(200)))
        if id == "me" {
            try await codex.refreshPlain()
            codex.rest.review(codex.defaultAccount)
        } else {
            _ = try await codex.refresh(codex.accounts[1])
            codex.rest.review(codex.accounts[1])
        }
    }

    @Test
    func `should rest a login whose weekly is spent until that window refills`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "me", primary: 5, secondary: 10, primaryReset: 1800, secondaryReset: 604_800)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)

        #expect(work.isResting)
        #expect(codex.accounts.watched.contains { $0.isDefault })
        #expect(!codex.accounts.watched.contains { $0 === work })
        #expect(codex.accounts.resting.contains { $0 === work })
    }

    @Test
    func `should refuse to fetch a resting login as resting, not as paused`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)

        do {
            _ = try await codex.refresh(work)
            Issue.record("expected the fetch to be refused")
        } catch let error as UsageError {
            guard case .resting = error else { Issue.record("wrong refusal: \(error)"); return }
        }
        #expect(!codex.accounts.paused.contains { $0 === work })
    }

    @Test
    func `should not rest when the spent weekly cannot say when it refills`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100)

        #expect(!work.isResting)
        #expect(codex.accounts.watched.contains { $0 === work })
    }

    @Test
    func `should rest nobody while the policy is off`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)

        #expect(!codex.rest.isOn)
        #expect(!work.isResting)
    }

    @Test
    func `should not judge a quota the person hid on the real login`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        stub.settings.setHiddenQuotaKeys(["weekly"], forProvider: "codex")
        try await usage(stub, codex, id: "work", primary: 5, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)

        #expect(!work.isResting)
    }

    @Test
    func `should not rest again after the person wakes the login`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        #expect(work.isResting)

        codex.rest.wake(work)
        #expect(!work.isResting)
        #expect(!codex.rest.mayRest(work))

        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        #expect(!work.isResting)
        #expect(codex.accounts.watched.contains { $0 === work })
    }

    @Test
    func `should drop every rest when the policy is turned off`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        #expect(work.isResting)

        codex.rest.isOn = false
        #expect(!work.isResting)
        #expect(codex.accounts.watched.contains { $0 === work })
    }

    @Test
    func `should come back once the window has passed`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        #expect(work.isResting)

        // Waking is the window's alone, read against the clock — nothing is
        // scheduled, so a past window is all it takes.
        work.restingUntil = Date.now.addingTimeInterval(-1)

        #expect(!work.isResting)
        #expect(codex.accounts.watched.contains { $0 === work })
        #expect(!codex.accounts.resting.contains { $0 === work })

        // Fetched again, and a fresh answer that is not spent drops the rest.
        try await usage(stub, codex, id: "work", primary: 5, secondary: 10, primaryReset: 1800, secondaryReset: 604_800)
        #expect(!work.isResting)
        #expect(work.restingUntil == nil)
        #expect(codex.accounts.watched.contains { $0 === work })
    }

    @Test
    func `should remember a rest across a relaunch`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)

        let again = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))
        #expect(again.accounts[1].isResting)
        #expect(again.rest.isOn)
        #expect(again.rest.mayRest(again.accounts[1]))
    }

    @Test
    func `should keep pausing winning over resting`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        #expect(work.isResting)

        work.pause()
        #expect(codex.accounts.resting.isEmpty)
        #expect(codex.accounts.paused.contains { $0 === work })
    }

    @Test
    func `should keep a resting login out of the switch-when-low targets`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        codex.rest.setMayRest(true, work)
        try await usage(stub, codex, id: "me", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        try await usage(stub, codex, id: "work", primary: 100, secondary: 100, primaryReset: 1800, secondaryReset: 604_800)
        codex.inUse?.switchWhenLow.isOn = true

        // The login in use ("me") is spent; the only other login is resting,
        // so nothing may be picked.
        let inUse = try #require(codex.inUse)
        #expect(inUse.switchWhenLow.next(from: inUse.login, among: inUse.logins) == nil)
    }
}
