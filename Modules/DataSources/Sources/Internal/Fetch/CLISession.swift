import Diagnostics
import Foundation

/// What a CLI worker remembers about its session between runs (#132): the
/// id of the session it runs in, and whether the installed CLI refused the
/// session flags. Held in memory, like `UsageMemory` — one per worker, and
/// the provider makes a worker per login, so each login keeps its own
/// session. A restart starts one new session; nothing is written to disk.
///
/// Concurrent fetches of one data source read and change this from
/// different tasks, so it is an actor.
actor SessionMemory {
    private(set) var id: String?
    private(set) var isRefused = false

    func remember(_ id: String) { self.id = id }

    func forget() { id = nil }

    /// Gives up on the session flags for this worker's lifetime.
    func refuse() {
        isRefused = true
        id = nil
    }
}

/// Runs one CLI call inside the worker's one session (#132).
///
/// The plan: no remembered id → create the session under a fresh id (the
/// `create` template) and remember it; a remembered id → resume it (`resume`
/// template); the CLI says the session is gone → forget it and create again;
/// the run exited non-zero naming a refused flag → give up on the flags for
/// this worker's lifetime and run the call's plain args from then on.
struct CLISessionRunner: Sendable {
    let call: CLICall
    let session: CLICall.Session
    /// The call's resolved working directory — `nil` to inherit.
    let directory: URL?
    let makeExecutor: CLIFetcher.MakeExecutor
    let memory: SessionMemory
    /// A fresh session id — a UUID in production.
    let nextID: @Sendable () -> String

    init(
        call: CLICall,
        session: CLICall.Session,
        directory: URL?,
        makeExecutor: @escaping CLIFetcher.MakeExecutor,
        memory: SessionMemory,
        nextID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.call = call
        self.session = session
        self.directory = directory
        self.makeExecutor = makeExecutor
        self.memory = memory
        self.nextID = nextID
    }

    /// Runs the call under the session plan and answers what the screen showed.
    func run() async throws -> CLIResult {
        guard await !memory.isRefused else { return try await plain() }
        if let remembered = await memory.id {
            let result = try await execute(session.resume, id: remembered)
            if Self.isRefused(result, tokens: session.unsupportedOn) {
                return try await giveUp()
            }
            if Self.isGone(result.output, tokens: session.recreateOn) {
                AppLog.probes.info("\(call.cli): the session is gone, creating a new one")
                await memory.forget()
                return try await create()
            }
            return result
        }
        return try await create()
    }

    /// Creates the session under a fresh id and remembers it. The session
    /// exists the moment the CLI boots, so the id is safe to keep even if the
    /// run's screen goes on to fail parsing.
    private func create() async throws -> CLIResult {
        let id = nextID()
        let result = try await execute(session.create, id: id)
        if Self.isRefused(result, tokens: session.unsupportedOn) {
            return try await giveUp()
        }
        await memory.remember(id)
        return result
    }

    /// Gives up on the flags for this worker's lifetime and runs the call the
    /// way it always has.
    private func giveUp() async throws -> CLIResult {
        AppLog.probes.info("\(call.cli) refused the session flags, continuing without one session")
        await memory.refuse()
        return try await plain()
    }

    private func plain() async throws -> CLIResult {
        try await execute([], id: "")
    }

    /// Appends the template's args — `{{id}}` filled, empty template for the
    /// plain run — to the call's own args.
    private func execute(_ template: [String], id: String) async throws -> CLIResult {
        try await makeExecutor(call).execute(
            binary: call.cli,
            args: call.args + template.map { $0.replacingOccurrences(of: "{{id}}", with: id) },
            input: call.input,
            timeout: call.timeout,
            workingDirectory: directory,
            autoResponses: call.autoResponses
        )
    }

    /// True when a run both failed and named a refused flag. The words alone
    /// prove nothing — a hook's transcript can carry them — but a CLI build
    /// that rejects an option exits non-zero.
    static func isRefused(_ result: CLIResult, tokens: [String]) -> Bool {
        guard result.exitCode != 0 else { return false }
        return matches(result.output, tokens: tokens)
    }

    /// True when the output says the stored session no longer exists.
    static func isGone(_ output: String, tokens: [String]) -> Bool {
        matches(output, tokens: tokens)
    }

    private static func matches(_ output: String, tokens: [String]) -> Bool {
        !tokens.isEmpty && tokens.contains { output.localizedCaseInsensitiveContains($0) }
    }
}
