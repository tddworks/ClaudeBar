import Foundation

// Shell-specific command and parsing rules for BinaryLocator.
public enum Shell: Sendable, Equatable {
    case posix
    case fish
    case nushell

    // MARK: - Detection

    public static func detect(from shellPath: String) -> Shell {
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

    public static var current: Shell {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return detect(from: shellPath)
    }

    // MARK: - Command Generation

    private static func sanitizedToolName(_ tool: String) -> String? {
        let pattern = "^[A-Za-z0-9._-]+$"
        guard tool.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return tool
    }

    public func whichArguments(for tool: String) -> [String] {
        guard let safeTool = Self.sanitizedToolName(tool) else {
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

    public func pathArguments() -> [String] {
        switch self {
        case .posix, .fish:
            return ["-l", "-c", "echo $PATH"]
        case .nushell:
            return ["-l", "-c", "$env.PATH | str join ':'"]
        }
    }

    // MARK: - Output Parsing

    public func parseWhichOutput(_ output: String) -> String? {
        let cleaned = Self.stripEscapeSequences(output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        switch self {
        case .posix, .fish:
            return cleaned
        case .nushell:
            // Reject table output that may have leaked through (check for box-drawing chars)
            let tableChars = CharacterSet(charactersIn: "│╭╮╯╰─┼┤├┬┴┌┐└┘")
            if cleaned.rangeOfCharacter(from: tableChars) != nil {
                return nil
            }
            return cleaned
        }
    }

    /// Strips ANSI escape sequences and OSC (Operating System Command) sequences
    /// that terminal emulators like iTerm2 inject via shell integration.
    private static func stripEscapeSequences(_ string: String) -> String {
        // Strip OSC sequences: ESC ] ... ST (where ST is ESC \ or BEL)
        // Also handle bare ] without ESC prefix (iTerm2 shell integration)
        var result = string
        // ESC ] ... (ESC \ | BEL)
        result = result.replacingOccurrences(
            of: "\\e\\].*?(?:\\e\\\\|\\u{07})",
            with: "",
            options: .regularExpression
        )
        // \x1b] ... (\x1b\ | \x07)
        result = result.replacingOccurrences(
            of: "\\x1b\\].*?(?:\\x1b\\\\|\\x07)",
            with: "",
            options: .regularExpression
        )
        // Bare ]NNNN;...  (iTerm2 sequences without ESC prefix)
        result = result.replacingOccurrences(
            of: "\\]\\d+;[^\n]*?(?=\\/|$)",
            with: "",
            options: .regularExpression
        )
        // Standard ANSI CSI sequences: ESC [ ... (letter)
        result = result.replacingOccurrences(
            of: "\\x1b\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        return result
    }

    public func parsePathOutput(_ output: String) -> String {
        Self.stripEscapeSequences(output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
