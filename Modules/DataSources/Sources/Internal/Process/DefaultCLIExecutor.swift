import Foundation

/// Default CLIExecutor that uses BinaryLocator and InteractiveRunner.
/// This is an adapter that wraps system APIs for CLI execution.
public struct DefaultCLIExecutor: CLIExecutor {
    /// Environment variable keys to exclude from the subprocess environment.
    /// When set, these keys are removed before the subprocess launches,
    /// preventing tokens like `CLAUDE_CODE_OAUTH_TOKEN` from being inherited.
    private let environmentExclusions: [String]

    /// Environment variables to set on the subprocess (after exclusions and
    /// terminal defaults). Probes pass `CLAUDEBAR_PROBE=1` so ClaudeBar's
    /// installed hook command can skip the sessions it spawns itself (#222).
    private let environmentAdditions: [String: String]

    /// Rule that tells the PTY run when the screen has settled. Without one, any
    /// idle gap ends the capture, truncating TUIs that fill in asynchronously
    /// (issue #271). Readable from tests so a fetch can be checked for pairing
    /// each command with the rule its own screen needs (#317).
    public let completionRule: CLICompletionRule?

    /// How long to wait after launch before sending input, so typed commands
    /// land on a settled TUI screen (see InteractiveRunner.Options.inputDelay).
    public let inputDelay: TimeInterval

    public init(
        environmentExclusions: [String] = [],
        environmentAdditions: [String: String] = [:],
        completionRule: CLICompletionRule? = nil,
        inputDelay: TimeInterval = 0.4
    ) {
        self.environmentExclusions = environmentExclusions
        self.environmentAdditions = environmentAdditions
        self.completionRule = completionRule
        self.inputDelay = inputDelay
    }

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
        let runner = InteractiveRunner()
        // Built here, on the task, so the `qualityOfService` default argument
        // reads the ambient `FetchContext` task local before we hop
        // off the cooperative pool below (task locals do not cross that hop).
        let options = InteractiveRunner.Options(
            timeout: timeout,
            workingDirectory: workingDirectory,
            arguments: args,
            autoResponses: autoResponses,
            environmentExclusions: environmentExclusions,
            environmentAdditions: environmentAdditions,
            completionRule: completionRule,
            inputDelay: inputDelay
        )
        let inputText = input ?? ""

        // `InteractiveRunner.run` polls with `usleep` and blocks for up to
        // `timeout`. Running it on the cooperative pool would park a thread that
        // every other provider's refresh needs, so hop to a dedicated queue.
        return try await withCheckedThrowingContinuation { continuation in
            Self.executionQueue.async {
                continuation.resume(
                    with: Swift.Result {
                        let result = try runner.run(
                            binary: binary,
                            input: inputText,
                            options: options
                        )
                        return CLIResult(output: result.output, exitCode: result.exitCode)
                    }
                )
            }
        }
    }

    /// Dedicated queue for blocking PTY runs, kept off the Swift cooperative
    /// pool. Concurrent so providers still refresh in parallel.
    private static let executionQueue = DispatchQueue(
        label: "com.tddworks.claudebar.cli-execution",
        qos: .utility,
        attributes: .concurrent
    )
}
