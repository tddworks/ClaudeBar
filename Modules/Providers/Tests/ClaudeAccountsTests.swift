import Crypto
import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// Claude's added accounts, all from `claude.json`: a second login lives in
/// its own config folder (`CLAUDE_CONFIG_DIR`), runs the same data sources
/// filled with that folder, and is told apart by the email its `.claude.json`
/// holds. The default login is untouched.
@MainActor
@Suite
struct ClaudeAccountsTests {
    private static let api = InMemoryProviderSettings(dataSourceKinds: ["claude": "api"])

    private func config(_ id: String, folder: URL, email: String) -> ProviderAccountConfig {
        ProviderAccountConfig(
            accountId: id, label: "", email: email,
            probeConfig: ["folder": folder.path, "accountId": email]
        )
    }

    /// Answers the usage API by bearer token: each login sees its own numbers.
    private func answerByToken(_ claude: ClaudeHarness, _ used: [String: Int]) {
        given(claude.network).request(.any).willProduce { @Sendable request in
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            let body = #"{ "five_hour": { "utilization": \#(used[token] ?? 0) } }"#
            return (Data(body.utf8), ClaudeHarness.response(200))
        }
    }

    // MARK: - Each login reads its own folder

    @Test
    func `should show an added login the usage of its own key and its own email`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "default-token")
        try claude.writeClaudeConfig(email: "me@example.com")
        let work = try claude.writeLogin(in: "work", email: "work@example.com", token: "work-token")
        answerByToken(claude, ["default-token": 20, "work-token": 70])
        let provider = try claude.provider(settings: Self.api, accounts: [config("w", folder: work, email: "work@example.com")])
        let (me, added) = (provider.accounts[0], provider.accounts[1])

        let mine = try await provider.refresh(me)
        let theirs = try await provider.refresh(added)

        #expect(added.id == "claude.w")
        #expect(mine.sessionQuota?.percentRemaining == 80)
        #expect(theirs.sessionQuota?.percentRemaining == 30)
        #expect(theirs.accountEmail == "work@example.com")
        #expect(theirs.providerId == "claude.w")
    }

    @Test
    func `should fail closed for a folder now signed in to someone else while the others keep their usage`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(accessToken: "default-token")
        let work = try claude.writeLogin(in: "work", email: "someone-else@example.com", token: "work-token")
        answerByToken(claude, ["default-token": 20, "work-token": 70])
        let provider = try claude.provider(settings: Self.api, accounts: [config("w", folder: work, email: "work@example.com")])
        let (me, added) = (provider.accounts[0], provider.accounts[1])

        try await provider.refresh(me)
        await #expect(throws: UsageError.self) { try await provider.refresh(added) }

        #expect(added.snapshot == nil)
        #expect(added.lastError?.localizedDescription.contains("signed in to someone else") == true)
        #expect(me.snapshot?.sessionQuota?.percentRemaining == 80)
    }

    @Test
    func `should run the CLI for an added login in its own folder without the default login's keys`() throws {
        let sources = try ProviderFactory.builtIn("claude").dataSources(forAccount: [
            "folder": "/Users/me/claude-work", "accountId": "work@example.com",
        ])

        for kind in ["cli", "cliCost"] {
            let source = try #require(sources.first { $0.kind == kind })
            guard case .cli(let call) = source.fetch else { Issue.record("\(kind) is not a CLI"); continue }
            #expect(call.environment.set["CLAUDE_CONFIG_DIR"] == "/Users/me/claude-work")
            #expect(call.environment.unset.contains("ANTHROPIC_API_KEY"))
            #expect(call.environment.unset.contains("CLAUDE_CODE_OAUTH_TOKEN"))
            #expect(source.context["signedInAs"]?.path == "/Users/me/claude-work/.claude.json")
            #expect(source.identity?.field == .context(file: "signedInAs", field: "id"))
            #expect(source.identity?.equals == "work@example.com")
        }
    }

    @Test
    func `should grant folder trust in the added login's own config`() throws {
        let sources = try ProviderFactory.builtIn("claude").dataSources(forAccount: [
            "folder": "/Users/me/claude-work", "accountId": "work@example.com",
        ])
        let cli = try #require(sources.first { $0.kind == "cli" })

        guard case .patchJSONFile(let path, _, _)? = cli.recover["folderTrustRequired"] else {
            Issue.record("no folder-trust recovery"); return
        }
        #expect(path == "/Users/me/claude-work/.claude.json")
    }

    @Test
    func `should leave the default login as it was when accounts are added`() throws {
        let definition = try ProviderFactory.builtIn("claude")
        let cli = try #require(try definition.asDefaultAccount("cli"))

        #expect(cli.identity == nil)
        #expect(cli.context["signedInAs"]?.path == ["${CLAUDE_CONFIG_DIR:-~/.claude}/.claude.json", "${CLAUDE_CONFIG_DIR:-~}/.claude.json"])
    }

    @Test
    func `should look up only the default login's own Keychain item, not one named for a folder`() throws {
        let definition = try ProviderFactory.builtIn("claude")
        let api = try #require(try definition.asDefaultAccount("api"))

        #expect(api.credential?.lookupOrder == [
            "${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json",
            "Keychain “Claude Code-credentials”",
            "$CLAUDE_CODE_OAUTH_TOKEN",
        ])
    }

    @Test
    func `should look up the Keychain item Claude Code names after an added login's folder`() throws {
        let sources = try ProviderFactory.builtIn("claude").dataSources(forAccount: [
            "folder": "/Users/me/work-claude", "accountId": "work@example.com",
        ])
        let api = try #require(sources.first { $0.kind == "api" })

        #expect(api.credential?.lookupOrder == [
            "/Users/me/work-claude/.credentials.json",
            "Keychain “Claude Code-credentials-91eb4f94”",
        ])
    }

    // MARK: - Guest passes are the default login's

    @Test
    func `should give guest passes to the default login only`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let work = try claude.writeLogin(in: "work", email: "work@example.com", token: "work-token")
        let provider = try claude.provider(
            settings: Self.api,
            accounts: [config("w", folder: work, email: "work@example.com")],
            guestPasses: GuestPasses(source: MockGuestPassSource(), plans: ["claudeMax"])
        )

        #expect(provider.accounts[1].guestPasses == nil)
        #expect(provider.defaultAccount.guestPasses != nil)
    }

    // MARK: - Add Account: choosing a signed-in folder

    @Test
    func `should save the folder and who is signed in to it when the person chooses a signed-in folder`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let settings = InMemoryProviderSettings()
        let work = try claude.writeLogin(in: "work", email: "work@example.com")
        let provider = try claude.provider(settings: settings)

        let added = try provider.accounts.add(signedInAt: work)

        #expect(added.email == "work@example.com")
        #expect(added.values == ["folder": work.resolvingSymlinksInPath().path, "accountId": "work@example.com"])
        #expect(settings.accounts(forProvider: "claude").map(\.accountId) == [added.accountId])
    }

    @Test
    func `should not add the same login twice`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let work = try claude.writeLogin(in: "work", email: "work@example.com")
        let again = try claude.writeLogin(in: "work-again", email: "work@example.com")
        let provider = try claude.provider()
        try provider.accounts.add(signedInAt: work)

        #expect(throws: UsageError.self) { try provider.accounts.add(signedInAt: work) }
        #expect(throws: UsageError.self) { try provider.accounts.add(signedInAt: again) }
        #expect(provider.accounts.count == 2)
    }

    @Test
    func `should refuse a folder with an email but no key as a login`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let folder = try claude.writeLogin(in: "half", email: "half@example.com")
        try FileManager.default.removeItem(at: folder.appendingPathComponent(".credentials.json"))
        let provider = try claude.provider()

        #expect(throws: UsageError.self) { try provider.accounts.add(signedInAt: folder) }
    }

    @Test
    func `should not add the default login again from another folder`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeClaudeConfig(email: "me@example.com")
        let copy = try claude.writeLogin(in: "copy", email: "me@example.com")
        let provider = try claude.provider()

        #expect(throws: UsageError.self) { try provider.accounts.add(signedInAt: copy) }
    }
}
