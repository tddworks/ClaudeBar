import Quotas
import Foundation
import System

/// Runs a command over plain pipes, without a terminal — for a CLI that
/// prints machine-readable output and needs no screen. A TUI goes through
/// `DefaultCLIExecutor` instead.
struct PipeCLIExecutor: CLIExecutor {
    private let change: ProcessEnvironment

    init(environment: ProcessEnvironment = ProcessEnvironment()) {
        self.change = environment
    }

    func locate(_ binary: String) -> String? {
        BinaryLocator.which(binary)
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
        let environment = Self.environment(binaryPath: path, change: change)
        let output = try await withThrowingTaskGroup(of: SubprocessSupport.Output.self) { group in
            group.addTask {
                try await SubprocessSupport.run(
                    executablePath: path,
                    arguments: args,
                    environment: SubprocessSupport.environment(environment),
                    workingDirectory: workingDirectory.map { FilePath($0.path) },
                    input: input
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw UsageError.timeout
            }
            guard let first = try await group.next() else { throw UsageError.timeout }
            // The loser is cancelled; a cancelled subprocess is terminated and reaped.
            group.cancelAll()
            return first
        }
        // Many CLIs report a problem on stderr; the mapping reads one text.
        return CLIResult(output: output.standardOutput + output.standardError, exitCode: output.exitCode)
    }

    /// The app's environment with a PATH that finds tools outside a login
    /// shell — an app started by launchd gets a minimal one, which breaks a
    /// script whose shebang is `/usr/bin/env node` — then the call's changes.
    static func environment(binaryPath: String, change: ProcessEnvironment) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var entries = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set(entries)
        let ownDirectory = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        for directory in [ownDirectory] + BinaryLocator.commonPaths where seen.insert(directory).inserted {
            entries.append(directory)
        }
        environment["PATH"] = entries.joined(separator: ":")
        for name in change.unset { environment.removeValue(forKey: name) }
        environment.merge(change.set) { _, value in value }
        return environment
    }
}
