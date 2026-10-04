import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// *Sign in with browser*: the definition's login runs into a new folder, and
/// the provider checks it as *Choose Signed-in Folder* does. ClaudeBar
/// remembers that it made the folder, so *Remove* takes the folder with it;
/// a folder the person chose is theirs.
@MainActor
@Suite
struct SignInAccountsTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("sign-in-accounts-\(UUID().uuidString)")

    /// A login that writes a Codex `auth.json` into the folder it is given.
    private func codexLogin(email: String?, accountId: String = "work", folders: InMemoryLoginFolders) -> AccountSignIn {
        let process = MockSignInProcess()
        given(process).run(executable: .any, arguments: .any, environment: .any, directory: .any, timeout: .any)
            .willProduce { @Sendable _, _, _, folder, _ in
                // The vendor's CLI writes its login into the folder it was given.
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if let email {
                    let claims = try JSONSerialization.data(withJSONObject: ["email": email])
                    let jwt = "h." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".s"
                    let auth = ["tokens": ["access_token": "t", "account_id": accountId, "id_token": jwt]]
                    try JSONSerialization.data(withJSONObject: auth).write(to: folder.appendingPathComponent("auth.json"))
                }
                return 0
            }
        return AccountSignIn(process: process, folders: folders, locate: { _ in "/usr/local/bin/codex" })
    }

    private func signIn(_ login: AccountSignIn, into codex: Provider) async throws -> Account {
        try await codex.signIn(with: login, under: root)
    }


    // MARK: - Signing in

    @Test
    func `signing in adds the login the new folder holds`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp(); try? FileManager.default.removeItem(at: root) }
        let codex = try stub.makeProvider("codex")

        let added = try await signIn(codexLogin(email: "work@example.com", folders: stub.folders), into: codex)

        let folder = try #require(added.folder)
        #expect(added.email == "work@example.com")
        #expect(added.values["chatgptAccountId"] == "work")
        #expect(folder.madeBy == .signIn)
        #expect(folder.url.deletingLastPathComponent().lastPathComponent == "codex")
        #expect(stub.settings.accounts(forProvider: "codex").first?.madeBy == .signIn)
    }

    @Test
    func `a sign-in that ends without a login leaves no folder`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp(); try? FileManager.default.removeItem(at: root) }
        let codex = try stub.makeProvider("codex")

        await #expect(throws: UsageError.self) { try await signIn(codexLogin(email: nil, folders: stub.folders), into: codex) }

        #expect(stub.folders.all.isEmpty)
        #expect(codex.accounts.count == 1)
    }

    @Test
    func `signing in to a login already listed leaves no folder`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp(); try? FileManager.default.removeItem(at: root) }
        let codex = try stub.makeProvider("codex")
        try await signIn(codexLogin(email: "work@example.com", folders: stub.folders), into: codex)

        await #expect(throws: UsageError.self) { try await signIn(codexLogin(email: "work@example.com", folders: stub.folders), into: codex) }

        #expect(stub.folders.all.count == 1)
    }

    // MARK: - Which folder goes with an account

    @Test
    func `a folder ClaudeBar made by signing in goes with its account`() {
        let folder = SignedInFolder.forSignIn(to: "codex", under: root)

        #expect(folder.goesWithAccount)
    }

    @Test
    func `a folder the person chose stays`() {
        let chosen = SignedInFolder(url: root.appendingPathComponent("codex/\(UUID().uuidString)"), madeBy: .folder)

        #expect(!chosen.goesWithAccount)
    }

    @Test
    func `a signed-in folder ClaudeBar did not name is never deleted`() {
        let renamed = SignedInFolder(url: URL(fileURLWithPath: "/Users/me/.codex"), madeBy: .signIn)

        #expect(!renamed.goesWithAccount)
    }

    // MARK: - Adding and removing

    @Test
    func `adding a login saves it`() throws {
        let settings = InMemoryProviderSettings()
        let codex = try Providers.make("codex", settings: settings)
        let work = ProviderAccountConfig(accountId: "a", label: "", email: "w@example.com",
                                         probeConfig: ["codexHome": "/tmp/a", "chatgptAccountId": "a"])

        codex.add(work)

        #expect(settings.accounts(forProvider: "codex") == [work])
    }

    @Test
    func `removing a signed-in login deletes the folder ClaudeBar made`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp(); try? FileManager.default.removeItem(at: root) }
        let codex = try stub.makeProvider("codex")
        let added = try await signIn(codexLogin(email: "work@example.com", folders: stub.folders), into: codex)

        codex.remove(added)

        #expect(stub.folders.all.isEmpty)
        #expect(stub.settings.accounts(forProvider: "codex").isEmpty)
    }

    @Test
    func `removing a login in a chosen folder keeps the folder`() throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let claims = try JSONSerialization.data(withJSONObject: ["email": "me@example.com"])
        let jwt = "h." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".s"
        let folder = stub.home.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": "t", "account_id": "me", "id_token": jwt]])
            .write(to: folder.appendingPathComponent("auth.json"))
        try stub.folders.create(folder)
        let codex = try stub.makeProvider("codex")
        let added = try codex.addAccount(signedInAt: folder)

        codex.remove(added)

        #expect(stub.folders.exists(folder))
    }

    // MARK: - Signing in again

    @Test
    func `signing in again runs the login in the folder ClaudeBar made, then refreshes it`() async throws {
        let stub = try StubbedProvider(dataSourceKind: "api", providerId: "codex")
        defer { stub.cleanUp(); try? FileManager.default.removeItem(at: root) }
        stub.answerHTTP(#"{"rate_limit":{"primary_window":{"used_percent":10}}}"#)
        let codex = try stub.makeProvider("codex")
        let added = try await signIn(codexLogin(email: "work@example.com", folders: stub.folders), into: codex)
        let launch = SignInLaunch()

        let usage = try await codex.signInAgain(added, with: launch.recording(folders: stub.folders))

        #expect(launch.directory == added.folder?.url.path)
        #expect(usage.sessionQuota?.percentRemaining == 90)
        #expect(stub.folders.exists(try #require(added.folder).url))
    }

    @Test
    func `a folder the person chose is never signed into by ClaudeBar`() async throws {
        let stub = try StubbedProvider(providerId: "codex")
        defer { stub.cleanUp() }
        let claims = try JSONSerialization.data(withJSONObject: ["email": "me@example.com"])
        let jwt = "h." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".s"
        let folder = stub.home.appendingPathComponent("mine")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": "t", "account_id": "me", "id_token": jwt]])
            .write(to: folder.appendingPathComponent("auth.json"))
        let codex = try stub.makeProvider("codex")
        let added = try codex.addAccount(signedInAt: folder)
        let launch = SignInLaunch()

        await #expect(throws: UsageError.self) { try await codex.signInAgain(added, with: launch.recording(folders: stub.folders)) }

        #expect(launch.directory == nil)
    }

    // MARK: - The ways to add, from the definition

    @Test
    func `codex and claude offer sign-in first, then choosing a folder`() throws {
        #expect(try Providers.builtIn("codex").accounts?.ways == [.signIn, .folder])
        #expect(try Providers.builtIn("claude").accounts?.ways == [.signIn, .folder])
    }

    @Test
    func `claude signs in with its own config folder and no inherited keys`() throws {
        let signIn = try #require(try Providers.builtIn("claude").accounts?.signIn)

        #expect(signIn.args == ["auth", "login", "--claudeai"])
        #expect(signIn.homeVariable == "CLAUDE_CONFIG_DIR")
        #expect(signIn.unset.contains("ANTHROPIC_API_KEY"))
    }

    @Test
    func `a sign-in with no folder rule to check it is refused on load`() {
        let json = #"{ "signIn": { "cli": "x", "args": [], "homeVariable": "X_HOME" } }"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProviderDefinition.Accounts.self, from: Data(json.utf8))
        }
    }
}

/// Where a login was run — for *Sign in again*, which runs in an existing folder.
private final class SignInLaunch: @unchecked Sendable {
    var directory: String?

    func recording(folders: InMemoryLoginFolders) -> AccountSignIn {
        let process = MockSignInProcess()
        given(process).run(executable: .any, arguments: .any, environment: .any, directory: .any, timeout: .any)
            .willProduce { @Sendable [self] _, _, _, folder, _ in
                directory = folder.path
                return 0
            }
        return AccountSignIn(process: process, folders: folders, locate: { _ in "/usr/local/bin/codex" })
    }
}
