import DataSources
import Foundation
import Mockable
@testable import Providers
import Quotas
import Testing

/// *In use* — which login new terminal sessions start with. Two Codex logins
/// are *me* (the plain login) and *work* (an added folder); choosing one
/// writes only its folder, and only new sessions follow it.
@MainActor
@Suite
struct InUseTests {
    // MARK: - Offered, or not

    @Test
    func `should offer In use, with the plain login in use, when the provider's CLI starts on a login's folder`() throws {
        let (stub, codex, _) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }

        let inUse = try #require(codex.inUse)
        #expect(inUse.login === codex.defaultAccount)
        #expect(inUse.command == TerminalCommand(name: "codex", environment: ["CODEX_HOME": "{{account.folder}}"]))
    }

    @Test
    func `should offer no In use when the provider's CLI has no login folder`() throws {
        let stub = try StubbedProvider(providerId: "gemini")
        defer { stub.cleanUp() }

        #expect(try stub.makeProvider("gemini").inUse == nil)
    }

    @Test
    func `should offer no In use when there is nowhere to record the choice`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }

        let codex = try ProviderFactory.make("codex", settings: stub.settings)

        #expect(codex.inUse == nil)
        #expect(codex.inUse == nil)
    }

    @Test
    func `should offer the plain login and every folder login, and no choice when there is only one`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let alone = try StubbedProvider(providerId: "codex")
        defer { alone.cleanUp() }

        #expect(codex.inUse?.logins.map(\.id) == [codex.defaultAccount.id, work.id])
        #expect(codex.inUse?.offersChoice == true)
        #expect(try alone.makeProvider("codex").inUse?.offersChoice == false)
    }

    // MARK: - Choosing

    @Test
    func `should put a chosen login in use and record only its folder`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }

        try #require(codex.inUse).use(work)

        #expect(codex.inUse?.isInUse(work) == true)
        #expect(codex.inUse?.isInUse(codex.defaultAccount) != true)
        #expect(stub.loginsInUse.folder(for: "codex") == work.folder?.url)
    }

    @Test
    func `should share the login in use between two providers that run the same CLI`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        // A second product running the same CLI, on the same record.
        let other = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))

        try #require(codex.inUse).use(work)
        try #require(other.inUse).use(other.defaultAccount)

        #expect(stub.loginsInUse.folder(for: "codex") == nil)
        let again = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))
        #expect(again.inUse?.login === again.defaultAccount)
        #expect(codex.inUse?.command.name == "codex")
    }

    @Test
    func `should keep the login in use after a relaunch`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try #require(codex.inUse).use(work)

        let again = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))

        #expect(again.inUse?.login.accountId == work.accountId)
    }

    @Test
    func `should clear the record when the person chooses the plain login`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try #require(codex.inUse).use(work)

        try #require(codex.inUse).use(codex.defaultAccount)

        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
        #expect(stub.loginsInUse.folder(for: "codex") == nil)
    }

    @Test
    func `should go back to the plain login when the login in use is removed`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try #require(codex.inUse).use(work)

        codex.accounts.remove(work)

        #expect(codex.inUse?.login === codex.defaultAccount)
        #expect(stub.loginsInUse.folder(for: "codex") == nil)
    }

    @Test
    func `should use the plain login when the record names a folder no login has`() throws {
        let (stub, _, _) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try stub.loginsInUse.use(URL(fileURLWithPath: "/tmp/gone"), for: "codex")

        let codex = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))

        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
    }

    @Test
    func `should refuse to put another provider's login in use`() throws {
        let (stub, codex, _) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let claudeStub = try StubbedProvider(providerId: "claude")
        defer { claudeStub.cleanUp() }
        let claude = try claudeStub.makeProvider("claude")

        #expect(throws: (any Error).self) { try codex.inUse?.use(claude.defaultAccount) }
        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
    }

    @Test
    func `should find a login by its name, its id, or default for the plain login`() throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }

        #expect(codex.accounts.named("Work") === work)
        #expect(codex.accounts.named(work.id) === work)
        #expect(codex.accounts.named("default") === codex.defaultAccount)
        #expect(codex.accounts.named("someone") == nil)
    }

    // MARK: - Worth switching

    @Test
    func `should suggest the login with more left when the login in use is low`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try await InUseFixture.usage(stub, codex, me: 92, work: 15)

        #expect(codex.inUse?.worthSwitchingTo === work)
    }

    @Test
    func `should suggest no switch to a login that shows only a balance`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try await InUseFixture.usage(stub, codex, me: 92, work: 15)
        work.snapshot = UsageSnapshot(providerId: "codex", quotas: [
            UsageQuota(left: .money(Money(12), of: nil), quotaType: .modelSpecific("Credits"), providerId: "codex"),
        ], capturedAt: Date())

        #expect(codex.inUse?.worthSwitchingTo == nil)
    }

    @Test
    func `should suggest no switch while the login in use has room or no login has more left`() async throws {
        let (stub, codex, _) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }

        try await InUseFixture.usage(stub, codex, me: 40, work: 10)
        #expect(codex.inUse?.worthSwitchingTo == nil)

        try await InUseFixture.usage(stub, codex, me: 92, work: 95)
        #expect(codex.inUse?.worthSwitchingTo == nil)
    }

    // MARK: - After each refresh: what is worth telling

    @Test
    func `should tell the person once, not on every refresh, that a login is worth switching to`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        try await InUseFixture.usage(stub, codex, me: 92, work: 15)
        let inUse = try #require(codex.inUse)

        #expect(try inUse.review() == .worthSwitching(from: codex.defaultAccount, to: work))
        #expect(try inUse.review() == nil)
    }

    @Test
    func `should tell the person again when the login in use runs low after recovering`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        try await InUseFixture.usage(stub, codex, me: 92, work: 15)
        _ = try inUse.review()

        try await InUseFixture.usage(stub, codex, me: 30, work: 15)
        #expect(try inUse.review() == nil)
        try await InUseFixture.usage(stub, codex, me: 95, work: 15)

        #expect(try inUse.review() == .worthSwitching(from: codex.defaultAccount, to: work))
    }

    @Test
    func `should switch and tell the person so when Switch when low is on`() async throws {
        let (stub, codex, work) = try InUseFixture.twoLogins()
        defer { stub.cleanUp() }
        let inUse = try #require(codex.inUse)
        inUse.switchWhenLow.isOn = true
        try await InUseFixture.usage(stub, codex, me: 95, work: 15)

        #expect(try inUse.review() == .switched(from: codex.defaultAccount, to: work))
        #expect(codex.inUse?.isInUse(work) == true)
    }
}

/// Codex with the plain login *me* and an added folder login *work*, and
/// their usage on demand.
@MainActor
enum InUseFixture {
    static func twoLogins() throws -> (StubbedProvider, Provider, Account) {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        try stub.writeCodexAuth(accountId: "me")
        let folder = stub.home.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let auth: [String: Any] = ["tokens": ["access_token": "token-work", "refresh_token": "refresh-work", "account_id": "work"],
                                   "last_refresh": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: auth).write(to: folder.appendingPathComponent("auth.json"))
        let config = ProviderAccountConfig(accountId: "work", label: "work", probeConfig: ["folder": folder.path, "accountId": "work"])
        stub.settings.addAccount(config, forProvider: "codex")
        let codex = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))
        return (stub, codex, codex.accounts[1])
    }

    /// Both logins refreshed with these percentages used.
    static func usage(_ stub: StubbedProvider, _ codex: Provider, me: Int, work: Int) async throws {
        stub.network.reset([.given])
        for (id, used) in [("me", me), ("work", work)] {
            given(stub.network).request(.matching { @Sendable in $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == id })
                .willReturn((Data(#"{"rate_limit":{"primary_window":{"used_percent":\#(used)}}}"#.utf8), StubbedProvider.response(200)))
        }
        try await codex.refreshPlain()
        try await codex.refresh(codex.accounts[1])
    }
}
