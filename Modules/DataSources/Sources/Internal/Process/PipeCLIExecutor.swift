import Quotas
import Foundation

/// Runs a command over plain pipes, without a terminal — for a CLI that
/// prints machine-readable output and needs no screen, and for a person's
/// script. The same on every platform: it finds a CLI and starts it as the
/// OS says. A TUI goes through the terminal runner.
struct PipeCLIExecutor: CLIExecutor {
    let change: ProcessEnvironment
    let installed: any InstalledPrograms
    let launch: any ChildLaunch

    func locate(_ binary: String) -> String? {
        installed.find(binary)
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
        let environment = SubprocessSupport.environment(launch.environment(for: path, change))
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
