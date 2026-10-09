import DataSources
import Quotas
import Foundation
import Mockable
@testable import Providers
import Testing

/// Codex's added accounts (#326) and its passive background (#216), all from
/// `codex.json`: the default login, and each login added by its folder.
@MainActor
@Suite
struct CodexAccountsTests {
    private static let usage = #"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":20}}}}"#
    /// What `codex app-server` 0.157 answers with no login (#525).
    private static let signedOut = #"{"id":2,"error":{"code":-32600,"message":"codex account authentication required to read rate limits"}}"#

    // MARK: - The default login stays passive until checked (#216)

    @Test
    func `should not start Codex in the background, and ask to click Refresh or Connect, before the person has checked it once (#216)`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage)
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.self) { try await codex.refreshPlain(.background) }

        #expect(stub.launches.count == 0)
        #expect(codex.defaultAccount.lastError?.localizedDescription.contains("Click Refresh or Connect") == true)
    }

    @Test
    func `should not start an unchecked Codex when the person opens the popover (#216)`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage)
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.self) { try await codex.refreshPlain(.passive) }

        #expect(stub.launches.count == 0)
    }

    @Test
    func `should keep refreshing Codex in the background once the person has refreshed it by hand`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage)
        let codex = try stub.make("codex")

        try await codex.refreshPlain()
        let background = try await codex.refreshPlain(.background)

        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == true)
        #expect(background.quota(for: .session)?.percentRemaining == 80)
        #expect(stub.launches.count == 2)
    }

    @Test
    func `should leave the Codex CLI unchecked when the login is read through the API`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(accountId: "account")
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10}}}"#)

        try await stub.make("codex").refreshPlain()

        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == nil)
    }

    @Test
    func `should ask to sign in, without trying the terminal, when Codex answers that it is signed out (#525)`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.signedOut)
        stub.answerTerminal("5h limit: 99% left")
        let codex = try stub.make("codex")

        await #expect(throws: UsageError.authenticationRequired) { try await codex.refreshPlain() }

        #expect(codex.defaultAccount.snapshot == nil)
    }

    @Test
    func `should stop starting Codex in the background once it answers that it is signed out, until the person refreshes (#525)`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        // A click: initialize, usage, the account. Then a poll: initialize, signed out.
        let answers = [
            #"{"id":1,"result":{}}"#, Self.usage, #"{"id":3,"result":{"account":null}}"#,
            #"{"id":1,"result":{}}"#, Self.signedOut,
        ]
        let received = Counter()
        given(stub.transport).send(.any).willReturn(())
        given(stub.transport).close().willReturn(())
        given(stub.transport).receive().willProduce { @Sendable in Data(answers[received.next() - 1].utf8) }
        let codex = try stub.make("codex")
        try await codex.refreshPlain()

        await #expect(throws: UsageError.authenticationRequired) { try await codex.refreshPlain(.background) }
        _ = try? await codex.refreshPlain(.background)

        #expect(stub.launches.count == 2)
        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == false)
    }

    @Test
    func `should show a Keychain login's email as the Codex CLI reports it`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        stub.answerRPC(Self.usage, account: #"{"id":3,"result":{"account":{"type":"chatgpt","email":"keychain@example.com"}}}"#)

        let usage = try await stub.make("codex").refreshPlain()

        #expect(usage.accountEmail == "keychain@example.com")
        #expect(usage.lowestQuota?.percentRemaining == 80)
    }

    // MARK: - Added accounts

    @Test
    func `should run Codex in an added login's own folder with file credentials only, and no API key`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "work@example.com", accountId: "work")
        stub.answerRPC(Self.usage)
        let (product, account) = try stub.makeAdded("codex", account: config("a", folder: folder, accountId: "work"))

        try await product.refresh(account, .background)

        let launch = try #require(stub.launches.last)
        #expect(launch.environment?["CODEX_HOME"] == folder.path)
        #expect(launch.environment?["OPENAI_API_KEY"] == nil)
        #expect(launch.arguments.contains(#"cli_auth_credentials_store="file""#))
        #expect(stub.settings.isOn("verifiedAtLeastOnce", forProvider: "codex") == nil)
    }

    @Test
    func `should keep each added login's own id, name and usage, and one login's failure its own (#326)`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let a = try writeLogin(in: stub.home, "a", email: "a@example.com", accountId: "a")
        stub.answerRPC(Self.usage)
        let (firstProduct, first) = try stub.makeAdded("codex", account: config("a", folder: a, accountId: "a", email: "a@example.com"))
        let (secondProduct, second) = try stub.makeAdded("codex", account: config(
            "b", folder: stub.home.appendingPathComponent("signed-out"), accountId: "b", email: "b@example.com"
        ))

        let usage = try await firstProduct.refresh(first)
        await #expect(throws: UsageError.self) { try await secondProduct.refresh(second) }

        #expect(first.id == "codex.a")
        #expect(second.id == "codex.b")
        #expect(firstProduct.lineupName(of: first) == "a@example.com")
        #expect(secondProduct.lineupName(of: second) == "b@example.com")
        #expect(usage.providerId == "codex.a")
        #expect(usage.quotas.first?.providerId == "codex.a")
        #expect(second.snapshot == nil)
        #expect(second.lastError != nil)
    }

    @Test
    func `should show the login's email whether Codex is read over RPC or the API`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "signed-in@example.com", accountId: "work")
        stub.answerRPC(Self.usage)
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10}}}"#)
        let (product, account) = try stub.makeAdded("codex", account: config("a", folder: folder, accountId: "work"))

        let viaRPC = try await product.refresh(account)
        product.configuration.use("api")
        let viaAPI = try await product.refresh(account)

        #expect(viaRPC.accountEmail == "signed-in@example.com")
        #expect(viaAPI.accountEmail == "signed-in@example.com")
    }

    @Test
    func `should be unavailable, without starting Codex, when an added login's folder is signed in to another account`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "other@example.com", accountId: "other")
        stub.answerRPC(Self.usage)
        given(stub.cli).locate(.any).willReturn("/usr/local/bin/codex")
        let (product, account) = try stub.makeAdded("codex", account: config("a", folder: folder, accountId: "original"))

        #expect(await product.isAvailable(account) == false)
        await #expect(throws: UsageError.self) { try await product.refresh(account) }

        #expect(stub.launches.count == 0)
        #expect(account.lastError?.localizedDescription.contains("original account") == true)
    }

    // MARK: - Adding an account by its folder

    @Test
    func `should add two folders as two logins with their own emails`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let a = try writeLogin(in: stub.home, "account a", email: "a@example.com", accountId: "account-a")
        let b = try writeLogin(in: stub.home, "account b", email: "b@example.com", accountId: "account-b")
        let codex = try stub.makeProvider("codex")

        let first = try codex.accounts.add(signedInAt: a)
        let second = try codex.accounts.add(signedInAt: b)

        #expect(first.email == "a@example.com")
        #expect(second.email == "b@example.com")
        #expect(first.accountId != second.accountId)
        #expect(first.values["chatgptAccountId"] == "account-a")
        #expect(first.values["codexHome"] == a.resolvingSymlinksInPath().path)
        #expect(first.madeBy == .folder)
    }

    @Test
    func `should refuse a folder whose login is already listed`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let a = try writeLogin(in: stub.home, "a", email: "same@example.com", accountId: "same")
        let b = try writeLogin(in: stub.home, "b", email: "same@example.com", accountId: "same")
        let codex = try stub.makeProvider("codex")
        try codex.accounts.add(signedInAt: a)

        #expect(throws: UsageError.executionFailed("This Codex account is already listed.")) {
            try codex.accounts.add(signedInAt: b)
        }
    }

    @Test
    func `should add one email in two workspaces as two logins`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let a = try writeLogin(in: stub.home, "a", email: "same@example.com", accountId: "workspace-a")
        let b = try writeLogin(in: stub.home, "b", email: "same@example.com", accountId: "workspace-b")
        let codex = try stub.makeProvider("codex")

        let first = try codex.accounts.add(signedInAt: a)
        let second = try codex.accounts.add(signedInAt: b)

        #expect(first.values["chatgptAccountId"] != second.values["chatgptAccountId"])
    }

    @Test
    func `should refuse a folder with no ChatGPT login and add nothing`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex")

        #expect(throws: UsageError.executionFailed("No ChatGPT account found in this folder. Sign in with Codex using file credential storage, then choose the folder again.")) {
            try codex.accounts.add(signedInAt: stub.home.appendingPathComponent("missing"))
        }
        #expect(codex.accounts.count == 1)
    }

    @Test
    func `should refuse a folder holding the default login`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(accountId: "me")
        let copy = try writeLogin(in: stub.home, "copy", email: "me@example.com", accountId: "me")
        let codex = try stub.makeProvider("codex")

        #expect(throws: UsageError.executionFailed("This Codex account is already listed.")) {
            try codex.accounts.add(signedInAt: copy)
        }
    }

    @Test
    func `should bring saved logins back under one Codex provider, each enabled or disabled on its own`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let a = try writeLogin(in: stub.home, "a", email: "a@example.com", accountId: "a")
        let b = try writeLogin(in: stub.home, "b", email: "b@example.com", accountId: "b")
        let before = try stub.makeProvider("codex")
        try before.accounts.add(signedInAt: a)
        try before.accounts.add(signedInAt: b)

        let codex = try stub.makeProvider("codex", accounts: stub.settings.accounts(forProvider: "codex"))
        let added = Array(codex.accounts.dropFirst())
        added[0].isEnabled = false

        #expect(codex.accounts.count == 3)
        #expect(codex.defaultAccount.id == "codex")
        #expect(added.map(codex.lineupName(of:)) == ["a@example.com", "b@example.com"])
        #expect(Set(codex.accounts.map(\.id)).count == 3)
        #expect(added[1].isEnabled)
        #expect(stub.settings.isEnabled(forProvider: added[0].id) == false)
    }

    // MARK: - One provider, many logins

    @Test
    func `should read added logins over RPC and the API only, from their own folder and account`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "work@example.com", accountId: "work")
        let codex = try stub.makeProvider("codex", accounts: [config("a", folder: folder, accountId: "work")])

        let defaultKinds = codex.dataSources(for: codex.defaultAccount).map(\.kind)
        let addedSources = codex.dataSources(for: codex.accounts[1])

        #expect(defaultKinds == ["rpc", "api", "tty"])
        #expect(addedSources.map(\.kind) == ["rpc", "api"])
        #expect(addedSources.first?.definition.fallback == nil)
        #expect(addedSources.first?.definition.requiresFiles == ["\(folder.path)/auth.json"])
        #expect(addedSources.first?.definition.identity?.equals == "work")
    }

    @Test
    func `should apply the person's data source choice to every login`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "work@example.com", accountId: "work")
        let codex = try stub.makeProvider("codex", accounts: [config("a", folder: folder, accountId: "work")])

        codex.configuration.use("api")

        #expect(codex.configuration.activeKind == "api")
        #expect(stub.settings.dataSourceKind(forProvider: "codex") == "api")
    }

    @Test
    func `should not add a login whose saved values are incomplete`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let codex = try stub.makeProvider("codex")

        let added = codex.accounts.add(ProviderAccountConfig(accountId: "a", label: "", probeConfig: ["codexHome": "/tmp/x"]))

        #expect(added == nil)
        #expect(codex.accounts.count == 1)
    }

    @Test
    func `should list a login once and keep the default login when asked to remove it`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let folder = try writeLogin(in: stub.home, "work", email: "work@example.com", accountId: "work")
        let codex = try stub.makeProvider("codex")
        let work = config("a", folder: folder, accountId: "work")

        let first = try #require(codex.accounts.add(work))
        let again = codex.accounts.add(work)
        codex.accounts.remove(codex.defaultAccount)
        codex.accounts.remove(first)

        #expect(again == nil)
        #expect(codex.accounts.map(\.id) == ["codex"])
    }

    @Test
    func `should show the worst enabled login's status and pick the login with the most left as best`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp() }
        try stub.writeCodexAuth(accountId: "me")
        let folder = try writeLogin(in: stub.home, "work", email: "work@example.com", accountId: "work")
        let codex = try stub.makeProvider("codex", accounts: [config("a", folder: folder, accountId: "work")])
        let me = codex.defaultAccount
        let work = codex.accounts[1]
        given(stub.network).request(.matching { @Sendable in $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "me" })
            .willReturn((Data(#"{"rate_limit":{"primary_window":{"used_percent":90}}}"#.utf8), StubbedProvider.response(200)))
        given(stub.network).request(.matching { @Sendable in $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "work" })
            .willReturn((Data(#"{"rate_limit":{"primary_window":{"used_percent":10}}}"#.utf8), StubbedProvider.response(200)))

        try await codex.refresh(me)
        try await codex.refresh(work)

        #expect(me.status == .critical)
        #expect(work.status == .healthy)
        #expect(codex.status == .critical)
        #expect(codex.accounts.best === work)

        me.isEnabled = false

        #expect(codex.status == .healthy)
    }

    // MARK: - Helpers

    private func config(_ id: String, folder: URL, accountId: String, email: String? = nil) -> ProviderAccountConfig {
        ProviderAccountConfig(
            accountId: id, label: "", email: email,
            probeConfig: ["codexHome": folder.path, "chatgptAccountId": accountId]
        )
    }

    /// A Codex folder signed in with file credentials: `auth.json` with an
    /// account id and an id token carrying the email.
    @discardableResult
    private func writeLogin(in root: URL, _ name: String, email: String, accountId: String) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let claims = try JSONSerialization.data(withJSONObject: ["email": email])
        let jwt = "header." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
        let auth: [String: Any] = [
            "tokens": ["access_token": "token-\(name)", "refresh_token": "refresh-\(name)",
                       "account_id": accountId, "id_token": jwt],
            "last_refresh": ISO8601DateFormatter().string(from: Date()),
        ]
        try JSONSerialization.data(withJSONObject: auth).write(to: folder.appendingPathComponent("auth.json"))
        return folder
    }
}
