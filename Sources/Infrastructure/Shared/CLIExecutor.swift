import Foundation
import Mockable

/// Result of executing a CLI command.
public struct CLIResult: Sendable, Equatable {
    public let output: String
    public let exitCode: Int32

    public init(output: String, exitCode: Int32 = 0) {
        self.output = output
        self.exitCode = exitCode
    }
}

/// Protocol for executing CLI commands.
/// From user's mental model: "Is this tool available?" and "Run it and get my stats"
@Mockable
public protocol CLIExecutor: Sendable {
    /// Finds a tool on the system. Returns the path if found, nil otherwise.
    func locate(_ binary: String) -> String?

    /// Runs a CLI command and returns the result.
    ///
    /// - Parameters:
    ///   - binary: The CLI tool to run
    ///   - args: Command-line arguments
    ///   - input: Text to send to the command
    ///   - timeout: Maximum time to wait
    ///   - workingDirectory: Directory to run in (nil = inherited)
    ///   - autoResponses: Automatic responses to prompts (prompt text → response to send)
    func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String]
    ) throws -> CLIResult
}
