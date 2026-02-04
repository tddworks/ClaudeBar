import Foundation

/// Default CLIExecutor that uses BinaryLocator and InteractiveRunner.
/// This is an adapter that wraps system APIs for CLI execution.
public struct DefaultCLIExecutor: CLIExecutor {
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
    ) throws -> CLIResult {
        let runner = InteractiveRunner()
        let options = InteractiveRunner.Options(
            timeout: timeout,
            workingDirectory: workingDirectory,
            arguments: args,
            autoResponses: autoResponses
        )

        let result = try runner.run(binary: binary, input: input ?? "", options: options)
        return CLIResult(output: result.output, exitCode: result.exitCode)
    }
}
