import Foundation
import Mockable

/// *Sign in with browser* as data: the vendor's own login command, and the
/// variable that points it at a folder of its own.
///
/// `{ "cli": "codex", "args": ["login"], "homeVariable": "CODEX_HOME",
///    "unset": ["OPENAI_API_KEY"], "alsoAt": ["/Applications/Codex.app/…/codex"] }`
public struct SignInCall: Sendable, Equatable, Codable {
    public let cli: String
    public let args: [String]
    /// Set to the new folder, so the login lands there and nowhere else.
    public let homeVariable: String
    /// Inherited variables that would pick another way to sign in — a key in
    /// the person's shell must not decide which account this becomes.
    public let unset: [String]
    /// Seconds to wait for the person to finish in the browser.
    public let timeout: TimeInterval
    /// Where else the CLI may be, when it ships inside a desktop app rather
    /// than on the PATH. `~` expands to the home directory.
    public let alsoAt: [String]

    public init(cli: String, args: [String], homeVariable: String, unset: [String] = [], timeout: TimeInterval = 300, alsoAt: [String] = []) {
        self.cli = cli
        self.args = args
        self.homeVariable = homeVariable
        self.unset = unset
        self.timeout = timeout
        self.alsoAt = alsoAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cli = try container.decode(String.self, forKey: .cli)
        args = try container.decode([String].self, forKey: .args)
        homeVariable = try container.decode(String.self, forKey: .homeVariable)
        unset = try container.decodeIfPresent([String].self, forKey: .unset) ?? []
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 300
        alsoAt = try container.decodeIfPresent([String].self, forKey: .alsoAt) ?? []
    }
}

/// Why a sign-in did not give a login.
public enum SignInError: Error, Equatable, LocalizedError {
    case cliNotFound(String)
    case folderExists
    case didNotFinish
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .cliNotFound(let cli):
            "`\(cli)` wasn't found. Install it, or choose a folder you already signed in to."
        case .folderExists:
            "That folder already exists, so ClaudeBar won't sign in there. Try again."
        case .didNotFinish:
            "Sign-in didn't finish. Try again and complete it in your browser."
        case .timedOut:
            "Sign-in timed out. Try again and complete it in your browser within five minutes."
        }
    }
}

/// Runs a login to the end: the process exits with a status, or is stopped
/// when the time is up (`SignInError.timedOut`) or the task is cancelled.
@Mockable
public protocol SignInProcess: Sendable {
    func run(executable: String, arguments: [String], environment: [String: String], directory: URL, timeout: TimeInterval) async throws -> Int32
}

/// Signs in to a vendor's CLI into a NEW folder ClaudeBar makes (0700). The
/// folder is the whole result: whoever checks it next decides whether it holds
/// a login. Nothing is left behind when the login does not finish.
public struct AccountSignIn: Sendable {
    private let process: any SignInProcess
    private let folders: any LoginFolders
    private let locate: @Sendable (String) -> String?
    private let isExecutable: @Sendable (String) -> Bool
    private let environment: @Sendable () -> [String: String]

    public init(
        process: any SignInProcess = FoundationSignInProcess(),
        folders: any LoginFolders = DiskLoginFolders(),
        locate: @escaping @Sendable (String) -> String? = { BinaryLocator.which($0) },
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        environment: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.process = process
        self.folders = folders
        self.locate = locate
        self.isExecutable = isExecutable
        self.environment = environment
    }

    public func signIn(_ call: SignInCall, into folder: URL) async throws {
        guard let executable = executable(for: call) else { throw SignInError.cliNotFound(call.cli) }
        guard !folders.exists(folder) else { throw SignInError.folderExists }
        try folders.create(folder)

        do {
            try await run(call, executable, in: folder)
        } catch {
            folders.delete(folder)
            throw error
        }
    }

    /// Signs in again in a folder this login already lives in — for a login
    /// whose session expired. The folder is kept whatever happens.
    public func signInAgain(_ call: SignInCall, in folder: URL) async throws {
        guard let executable = executable(for: call) else { throw SignInError.cliNotFound(call.cli) }
        guard folders.exists(folder) else { throw SignInError.didNotFinish }
        try await run(call, executable, in: folder)
    }

    /// The login, pointed at `folder` and nothing inherited that would pick
    /// another way in.
    private func run(_ call: SignInCall, _ executable: String, in folder: URL) async throws {
        var variables = environment()
        for name in call.unset { variables.removeValue(forKey: name) }
        variables[call.homeVariable] = folder.path
        let status = try await process.run(executable: executable, arguments: call.args, environment: variables,
                                           directory: folder, timeout: call.timeout)
        guard status == 0 else { throw SignInError.didNotFinish }
    }

    private func executable(for call: SignInCall) -> String? {
        if let found = locate(call.cli) { return found }
        let home = environment()["HOME"] ?? NSHomeDirectory()
        return call.alsoAt
            .map { $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
            .first(where: isExecutable)
    }
}

/// A login as a child process. Its output is never read or logged: a login's
/// diagnostics can carry a token.
public struct FoundationSignInProcess: SignInProcess {
    public init() {}

    public func run(executable: String, arguments: [String], environment: [String: String], directory: URL, timeout: TimeInterval) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            try Task.checkCancellation()
            guard Date() < deadline else { throw SignInError.timedOut }
            try await Task.sleep(for: .milliseconds(200))
        }
        return process.terminationStatus
    }
}
