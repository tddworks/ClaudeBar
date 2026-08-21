import Domain
import Foundation
import Subprocess
import System

/// Shared plumbing for probes that shell out through `Subprocess`.
///
/// The PTY runners (`InteractiveRunner`, `PersistentSession`) deliberately stay
/// on `Foundation.Process`: they need `openpty` so CLI tools believe they are
/// attached to a terminal, and Subprocess has no pseudo-terminal support as of
/// 1.0.0. Everything that only needs pipes routes through here instead, which
/// removes the read-after-wait deadlock hazard and reaps the child properly.
enum SubprocessSupport {

    /// Default cap on collected output. Explicit because Subprocess 1.0 requires
    /// a limit at every call site rather than silently truncating.
    static let defaultOutputLimit = 1 << 20  // 1 MiB

    /// The outcome of a run, in copyable form.
    ///
    /// `ExecutionResult` is `~Copyable`, which makes it awkward to hand across
    /// `do`/`catch` boundaries; callers get this plain value instead.
    struct Output: Sendable {
        let standardOutput: String
        let standardError: String
        let exitCode: Int32

        var isSuccess: Bool { exitCode == 0 }
    }

    /// Bridges a plain environment dictionary into Subprocess's typed form.
    ///
    /// `Environment.Key` exposes only a string-literal initializer publicly; it
    /// accepts runtime strings just the same.
    static func environment(_ variables: [String: String]) -> Environment {
        .custom(
            Dictionary(
                variables.map { (Environment.Key(stringLiteral: $0.key), $0.value) },
                // Keys are case-sensitive on Darwin, so collisions are not
                // expected — resolve deterministically rather than trapping.
                uniquingKeysWith: { _, last in last }
            )
        )
    }

    /// Runs an executable and collects its output as text.
    ///
    /// A non-zero exit code is returned, not thrown — callers decide whether it
    /// matters, matching how the `Process`-based code behaved.
    ///
    /// - Parameter qualityOfService: Defaults to the ambient probe QoS so
    ///   background refreshes keep spawning throttled process trees (issue #204).
    static func run(
        executablePath: String,
        arguments: [String],
        environment: Environment = .inherit,
        workingDirectory: FilePath? = nil,
        input: String? = nil,
        outputLimit: Int = defaultOutputLimit,
        qualityOfService: QualityOfService = ProbeExecutionContext.qualityOfService
    ) async throws -> Output {
        var platformOptions = PlatformOptions()
        platformOptions.qualityOfService = qualityOfService

        let result = try await Subprocess.run(
            .path(FilePath(executablePath)),
            arguments: Arguments(arguments),
            environment: environment,
            workingDirectory: workingDirectory,
            platformOptions: platformOptions,
            // An empty string still closes stdin immediately, matching the
            // previous behaviour of writing nothing and closing the pipe.
            input: .string(input ?? ""),
            output: .string(limit: outputLimit),
            error: .string(limit: outputLimit)
        )

        return Output(
            standardOutput: result.standardOutput,
            standardError: result.standardError,
            exitCode: result.terminationStatus.foundationExitCode
        )
    }
}

extension TerminationStatus {
    /// Exit code using `Foundation.Process` conventions.
    ///
    /// `Process.terminationStatus` reports the signal number when a child is
    /// killed by a signal, so mirroring that keeps `CLIResult.exitCode` meaning
    /// exactly what it did before the migration.
    var foundationExitCode: Int32 {
        switch self {
        case let .exited(code):
            Int32(code)
        case let .signaled(signal):
            Int32(signal)
        }
    }
}
