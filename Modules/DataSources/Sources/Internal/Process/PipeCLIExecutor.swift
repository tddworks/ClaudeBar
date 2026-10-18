import Quotas
import Foundation

/// What a platform's `Processes` adapter tells the pipe runner and the
/// conversation: how it finds a CLI, the environment a child starts with,
/// and how it ends a child a conversation started.
struct PipeFacts: Sendable {
    /// A CLI's full path, as `Processes.locate`.
    let locate: @Sendable (String) -> String?
    /// The environment a child at `path` starts with: the app's, with `change` applied.
    let environment: @Sendable (_ path: String, _ change: ProcessEnvironment) -> [String: String]
    /// Ends a child a conversation started, within a bound.
    let end: @Sendable (Process) -> Void
}

/// Runs a command over plain pipes, without a terminal — for a CLI that
/// prints machine-readable output and needs no screen, and for a person's
/// script. The same on every platform; a TUI goes through the terminal runner.
struct PipeCLIExecutor: CLIExecutor {
    let change: ProcessEnvironment
    let facts: PipeFacts

    func locate(_ binary: String) -> String? {
        facts.locate(binary)
    }

    func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String]
    ) async throws -> CLIResult {
        guard let path = locate(binary) else { throw UsageError.cliNotFound(binary) }
        let environment = SubprocessSupport.environment(facts.environment(path, change))
        let output = try await withThrowingTaskGroup(of: SubprocessSupport.Output.self) { group in
            // Cancelled, swift-subprocess ends the program.
            group.addTask {
                try await SubprocessSupport.run(executablePath: path, arguments: args, environment: environment,
                                                workingDirectory: workingDirectory, input: input)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw UsageError.timeout
            }
            guard let first = try await group.next() else { throw UsageError.timeout }
            // The loser is cancelled; a cancelled run ends its program.
            group.cancelAll()
            return first
        }
        // Many CLIs report a problem on stderr; the mapping reads one text.
        return CLIResult(output: output.standardOutput + output.standardError, exitCode: output.exitCode)
    }
}
