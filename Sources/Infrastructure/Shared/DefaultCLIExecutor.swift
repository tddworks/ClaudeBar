import Foundation

/// Default CLIExecutor that uses BinaryLocator and InteractiveRunner.
/// This is an adapter that wraps system APIs for CLI execution.
public struct DefaultCLIExecutor: CLIExecutor {
    /// Environment variable keys to exclude from the subprocess environment.
    /// When set, these keys are removed before the subprocess launches,
    /// preventing tokens like `CLAUDE_CODE_OAUTH_TOKEN` from being inherited.
    private let environmentExclusions: [String]

    public init(environmentExclusions: [String] = []) {
        self.environmentExclusions = environmentExclusions
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
        // reads the ambient `ProbeExecutionContext` task local before we hop
        // off the cooperative pool below (task locals do not cross that hop).
        let options = InteractiveRunner.Options(
            timeout: timeout,
            workingDirectory: workingDirectory,
            arguments: args,
            autoResponses: autoResponses,
            environmentExclusions: environmentExclusions
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
