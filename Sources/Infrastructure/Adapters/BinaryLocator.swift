import Foundation

/// Finds where CLI tools are installed on the system.
///
/// Many AI coding assistants (Claude, Codex, Gemini) are installed via npm, Homebrew,
/// or other package managers in non-standard locations. This locator searches common
/// installation paths to find them.
///
/// Usage:
/// ```swift
/// if let path = BinaryLocator.which("claude") {
///     print("Claude CLI found at: \(path)")
/// }
/// ```
public struct BinaryLocator: Sendable {
    public init() {}

    /// Finds a tool by name, searching common installation paths.
    ///
    /// - Parameter tool: The name of the CLI tool (e.g., "claude", "codex", "gemini")
    /// - Returns: The full path to the tool if found, nil otherwise
    public func locate(_ tool: String) -> String? {
        Self.which(tool)
    }

    /// Finds a tool by name (static convenience).
    ///
    /// - Parameter tool: The name of the CLI tool
    /// - Returns: The full path to the tool if found, nil otherwise
    public static func which(_ tool: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [tool]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths()
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty else { return nil }
        return path
    }

    // MARK: - Internal

    /// Common locations where CLI tools are typically installed.
    /// Includes Homebrew, npm global, bun, nvm, and standard Unix paths.
    static func searchPaths() -> String {
        let home = NSHomeDirectory()
        let commonLocations = [
            "\(home)/.claude/local",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.nvm/versions/node/*/bin",
            "/usr/bin",
            "/bin",
        ]
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (commonLocations + [existingPath]).joined(separator: ":")
    }
}