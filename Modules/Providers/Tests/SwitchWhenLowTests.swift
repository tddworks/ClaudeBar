import Foundation
@testable import Providers
import Quotas
import Testing

/// *Switch when low* — the opt-in policy that moves new sessions off a login
/// running out, to the ticked login with the most left.
@MainActor
@Suite
struct SwitchWhenLowTests {
    @Test
    func `should switch nowhere until the person turns it on`() async throws {
        let (stub, codex, _) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        try await InUseFixture.usage(stub, codex, me: 95, work: 10)

        #expect(inUse.switchWhenLow.isOn == false)
        #expect(inUse.switchWhenLow.next(from: inUse.login, among: inUse.logins) == nil)
    }

    @Test
    func `should switch to the ticked login with the most left when the login in use falls below the threshold`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.below = 10
        try await InUseFixture.usage(stub, codex, me: 95, work: 10)

        #expect(inUse.switchWhenLow.next(from: inUse.login, among: inUse.logins) === work)
    }

    @Test
    func `should not switch when the login in use is above the threshold`() async throws {
        let (stub, codex, _) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.below = 5
        try await InUseFixture.usage(stub, codex, me: 90, work: 10)

        #expect(inUse.switchWhenLow.next(from: inUse.login, among: inUse.logins) == nil)
    }

    @Test
    func `should not switch to a login that shows only a balance, for its room has no percent to compare`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.below = 10
        try await InUseFixture.usage(stub, codex, me: 95, work: 10)
        work.snapshot = UsageSnapshot(providerId: "codex", quotas: [
            UsageQuota(left: .money(Money(12), of: nil), quotaType: .modelSpecific("Credits"), providerId: "codex"),
        ], capturedAt: Date())

        #expect(inUse.switchWhenLow.next(from: inUse.login, among: inUse.logins) == nil)
    }

    @Test
    func `should never switch to a login the person unticked`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        inUse.switchWhenLow.isOn = true
        inUse.switchWhenLow.setMayPick(false, work)
        try await InUseFixture.usage(stub, codex, me: 95, work: 10)

        #expect(inUse.switchWhenLow.mayPick(work) == false)
        #expect(inUse.switchWhenLow.next(from: inUse.login, among: inUse.logins) == nil)
    }

    @Test
    func `should remember whether it is on, its threshold and the unticked logins across a relaunch`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let policy = try #require(codex.inUse?.switchWhenLow)
        policy.isOn = true
        policy.below = 20
        policy.setMayPick(false, work)

        let again = try #require(try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex")).inUse)

        #expect(again.switchWhenLow.isOn)
        #expect(again.switchWhenLow.below == 20)
        #expect(again.switchWhenLow.mayPick(again.logins[1]) == false)
        #expect(again.switchWhenLow.mayPick(again.login))
    }
}
