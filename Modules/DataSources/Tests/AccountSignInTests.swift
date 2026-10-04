import DataSources
import Foundation
import Mockable
import Testing

/// *Sign in with browser*: the vendor's own login, run into a new folder
/// ClaudeBar makes — never an existing one, and nothing left behind when it
/// does not finish.
@Suite
struct AccountSignInTests {
    private let folder = URL(fileURLWithPath: "/accounts/codex/new-login")

    private let call = SignInCall(
        cli: "codex", args: ["login"], homeVariable: "CODEX_HOME",
        unset: ["OPENAI_API_KEY"], alsoAt: []
    )

    /// What the login was started with.
    private final class Launch: @unchecked Sendable {
        var executable: String?
        var arguments: [String]?
        var environment: [String: String]?
        var directory: URL?
        var timeout: TimeInterval?
    }

    private func recording(_ launch: Launch, exitStatus: Int32 = 0) -> MockSignInProcess {
        let process = MockSignInProcess()
        given(process).run(executable: .any, arguments: .any, environment: .any, directory: .any, timeout: .any)
            .willProduce { executable, arguments, environment, directory, timeout in
                launch.executable = executable
                launch.arguments = arguments
                launch.environment = environment
                launch.directory = directory
                launch.timeout = timeout
                return exitStatus
            }
        return process
    }

    private func signIn(
        _ process: MockSignInProcess,
        folders: InMemoryLoginFolders = InMemoryLoginFolders(),
        found: [String: String] = ["codex": "/usr/local/bin/codex"],
        executables: Set<String> = []
    ) -> AccountSignIn {
        AccountSignIn(
            process: process,
            folders: folders,
            locate: { found[$0] },
            isExecutable: { executables.contains($0) },
            environment: { ["PATH": "/usr/bin", "OPENAI_API_KEY": "sk-shared", "HOME": "/Users/me"] }
        )
    }

    @Test
    func `the login runs in a new folder with only its home variable added`() async throws {
        let launch = Launch()
        let folders = InMemoryLoginFolders()

        try await signIn(recording(launch), folders: folders).signIn(call, into: folder)

        #expect(launch.executable == "/usr/local/bin/codex")
        #expect(launch.arguments == ["login"])
        #expect(launch.environment == ["PATH": "/usr/bin", "HOME": "/Users/me", "CODEX_HOME": folder.path])
        #expect(launch.directory == folder)
        #expect(launch.timeout == 300)
        #expect(folders.all == [folder.path])
    }

    @Test
    func `a cli bundled inside an app is found where the definition says`() async throws {
        let launch = Launch()
        let bundled = SignInCall(cli: "codex", args: ["login"], homeVariable: "CODEX_HOME",
                                 alsoAt: ["~/Applications/Codex.app/Contents/Resources/codex"])

        try await signIn(recording(launch), found: [:], executables: ["/Users/me/Applications/Codex.app/Contents/Resources/codex"])
            .signIn(bundled, into: folder)

        #expect(launch.executable == "/Users/me/Applications/Codex.app/Contents/Resources/codex")
    }

    @Test
    func `without the cli nothing is made`() async throws {
        let folders = InMemoryLoginFolders()

        await #expect(throws: SignInError.cliNotFound("codex")) {
            try await signIn(MockSignInProcess(), folders: folders, found: [:]).signIn(call, into: folder)
        }
        #expect(folders.all.isEmpty)
    }

    @Test
    func `a login that does not finish leaves no folder`() async throws {
        let folders = InMemoryLoginFolders()

        await #expect(throws: SignInError.didNotFinish) {
            try await signIn(recording(Launch(), exitStatus: 1), folders: folders).signIn(call, into: folder)
        }
        #expect(folders.all.isEmpty)
    }

    @Test
    func `a login that times out leaves no folder`() async throws {
        let folders = InMemoryLoginFolders()
        let process = MockSignInProcess()
        given(process).run(executable: .any, arguments: .any, environment: .any, directory: .any, timeout: .any)
            .willThrow(SignInError.timedOut)

        await #expect(throws: SignInError.timedOut) { try await signIn(process, folders: folders).signIn(call, into: folder) }

        #expect(folders.all.isEmpty)
    }

    @Test
    func `an existing folder is never signed into`() async throws {
        let folders = InMemoryLoginFolders([folder])

        await #expect(throws: SignInError.folderExists) {
            try await signIn(MockSignInProcess(), folders: folders).signIn(call, into: folder)
        }
        #expect(folders.all == [folder.path])
    }

    @Test
    func `the sign-in command reads from a definition`() throws {
        let json = #"{ "cli": "claude", "args": ["auth", "login"], "homeVariable": "CLAUDE_CONFIG_DIR" }"#

        let decoded = try JSONDecoder().decode(SignInCall.self, from: Data(json.utf8))

        #expect(decoded.unset.isEmpty)
        #expect(decoded.alsoAt.isEmpty)
        #expect(decoded.timeout == 300)
    }
}

/// The real disk behind `LoginFolders`: private, new, and gone when deleted.
@Suite
struct DiskLoginFoldersTests {
    @Test
    func `a login folder is made private, never over another, and can be deleted`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("login-folders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("codex/login")
        let disk = DiskLoginFolders()

        try disk.create(folder)
        let permissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int

        #expect(permissions == 0o700)
        #expect(throws: SignInError.folderExists) { try disk.create(folder) }
        disk.delete(folder)
        #expect(!disk.exists(folder))
    }
}
