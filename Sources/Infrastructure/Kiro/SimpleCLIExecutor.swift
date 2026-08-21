import Domain
import Foundation
import System

/// Simple CLI executor that runs commands over plain pipes, without a PTY.
///
/// Used by tools that emit machine-readable output and do not need to believe
/// they are attached to a terminal. Providers that do need that go through
/// `DefaultCLIExecutor`/`InteractiveRunner` instead.
public struct SimpleCLIExecutor: CLIExecutor {
    public init() {}
    
    public func locate(_ binary: String) -> String? {
        BinaryLocator.which(binary)
    }
    
    public func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String]
    ) async throws -> CLIResult {
        guard let binaryPath = locate(binary) else {
            throw ProbeError.cliNotFound(binary)
        }
        
        let result: SubprocessSupport.Output
        do {
            result = try await withThrowingTaskGroup(of: SubprocessSupport.Output.self) { group in
                group.addTask {
                    try await SubprocessSupport.run(
                        executablePath: binaryPath,
                        arguments: args,
                        environment: SubprocessSupport.environment(
                            Self.augmentedEnvironment(binaryPath: binaryPath)
                        ),
                        workingDirectory: workingDirectory.map { FilePath($0.path) },
                        input: input
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw ProbeError.executionFailed("Command timed out after \(timeout) seconds")
                }

                guard let first = try await group.next() else {
                    throw ProbeError.executionFailed("Command produced no result")
                }
                // Whichever task lost the race is cancelled here. If that is the
                // subprocess, cancellation drives Subprocess's teardown sequence
                // (SIGTERM, then SIGKILL) and the child is reaped — the previous
                // `terminate()`-and-throw left a zombie behind.
                group.cancelAll()
                return first
            }
        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.executionFailed("Failed to run \(binary): \(error.localizedDescription)")
        }

        // Combine stdout and stderr, as before: Kiro reports errors on stderr and
        // callers parse a single blob.
        return CLIResult(
            output: result.standardOutput + result.standardError,
            exitCode: result.exitCode
        )
    }

    /// Builds the child environment with a PATH that works outside a login
    /// shell. Menu bar apps launched by launchd inherit a minimal PATH
    /// (`/usr/bin:/bin:...`), which breaks script CLIs whose shebang resolves
    /// a runtime via `/usr/bin/env` (e.g. `#!/usr/bin/env bun` for omp).
    /// Appends the common install directories plus the resolved binary's own
    /// directory (runtimes usually live next to the tools they run).
    static func augmentedEnvironment(binaryPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"

        var entries = currentPath.split(separator: ":").map(String.init)
        var seen = Set(entries)

        let binaryDirectory = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        for directory in [binaryDirectory] + BinaryLocator.commonPaths where seen.insert(directory).inserted {
            entries.append(directory)
        }

        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }
}
