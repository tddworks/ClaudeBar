import Foundation

// Shell-specific command and parsing rules for BinaryLocator.
enum Shell: Sendable, Equatable {
    case posix
    case fish
    case nushell

    // MARK: - Detection

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

    static var current: Shell {
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

    func whichArguments(for tool: String) -> [String] {
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

    func pathArguments() -> [String] {
        switch self {
        case .posix, .fish:
            return ["-l", "-c", "echo $PATH"]
        case .nushell:
            return ["-l", "-c", "$env.PATH | str join ':'"]
        }
    }

    // MARK: - Output Parsing

    func parseWhichOutput(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch self {
        case .posix, .fish:
            return trimmed
        case .nushell:
            // Reject table output that may have leaked through (check for box-drawing chars)
            let tableChars = CharacterSet(charactersIn: "│╭╮╯╰─┼┤├┬┴┌┐└┘")
            if trimmed.rangeOfCharacter(from: tableChars) != nil {
                return nil
            }
            return trimmed
        }
    }

    func parsePathOutput(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
