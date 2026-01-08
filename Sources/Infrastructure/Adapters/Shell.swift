import Foundation

/// Represents different shell types with their specific command syntax.
///
/// The user's login shell determines how commands like `which` and environment
/// variable access work. This enum encapsulates shell-specific behavior so
/// `BinaryLocator` can work correctly across different shells.
enum Shell: Sendable, Equatable {
    case posix
    case fish
    case nushell

    // MARK: - Detection

    /// Detects the shell type from a shell executable path.
    ///
    /// - Parameter shellPath: Full path to the shell (e.g., "/bin/zsh", "/opt/homebrew/bin/nu")
    /// - Returns: The detected shell type, defaults to `.posix` for unknown shells
    static func detect(from shellPath: String) -> Shell {
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent.lowercased()

        switch shellName {
        case "nu", "nushell":
            return .nushell
        case "fish":
            return .fish
        default:
            return .posix
        }
    }

    /// Returns the current user's shell type based on the `SHELL` environment variable.
    static var current: Shell {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return detect(from: shellPath)
    }

    // MARK: - Command Generation

    /// Validates that a tool name is safe for shell execution.
    ///
    /// Only allows alphanumeric characters, underscores, hyphens, and dots.
    /// Returns nil if the tool name contains shell metacharacters.
    ///
    /// - Parameter tool: The tool name to validate
    /// - Returns: The validated tool name, or nil if unsafe
    private static func sanitizedToolName(_ tool: String) -> String? {
        let pattern = "^[A-Za-z0-9._-]+$"
        guard tool.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return tool
    }

    /// Returns the arguments to run a `which` command for finding a tool's path.
    ///
    /// - Parameter tool: The name of the CLI tool to find (e.g., "claude", "codex")
    /// - Returns: Arguments to pass to the shell executable. Returns arguments that will
    ///   safely fail if the tool name contains shell metacharacters.
    func whichArguments(for tool: String) -> [String] {
        guard let safeTool = Self.sanitizedToolName(tool) else {
            // Return empty which command that will fail safely
            return ["-l", "-c", "which ''"]
        }

        switch self {
        case .posix, .fish:
            return ["-l", "-c", "which \(safeTool)"]
        case .nushell:
            // ^which calls the external binary, avoiding Nushell's table-outputting built-in
            return ["-l", "-c", "^which \(safeTool)"]
        }
    }

    /// Returns the arguments to get the PATH environment variable.
    ///
    /// - Returns: Arguments to pass to the shell executable
    func pathArguments() -> [String] {
        switch self {
        case .posix, .fish:
            return ["-l", "-c", "echo $PATH"]
        case .nushell:
            return ["-l", "-c", "$env.PATH | str join ':'"]
        }
    }

    // MARK: - Output Parsing

    /// Parses the output of the `which` command to extract the binary path.
    ///
    /// - Parameter output: Raw output from the shell command
    /// - Returns: The clean path to the binary, or `nil` if not found/parseable
    func parseWhichOutput(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch self {
        case .posix, .fish:
            return trimmed
        case .nushell:
            // Reject table output that may have leaked through (check for box-drawing chars)
            let tableChars = CharacterSet(charactersIn: "│╭╮╯╰─┼┤├")
            if trimmed.rangeOfCharacter(from: tableChars) != nil {
                return nil
            }
            return trimmed
        }
    }

    /// Parses the output of the PATH command.
    ///
    /// - Parameter output: Raw output from the shell command
    /// - Returns: The PATH string (colon-separated)
    func parsePathOutput(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
