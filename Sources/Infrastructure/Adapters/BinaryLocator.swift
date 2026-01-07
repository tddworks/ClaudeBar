import Foundation

/// Finds where CLI tools are installed on the system.
///
/// Uses the user's login shell to run `which`, ensuring access to the full PATH
/// from their shell configuration (.zshrc, .bashrc, etc.). This supports tools
/// installed via nix-darwin, Homebrew, npm, and other package managers.
///
/// Usage:
/// ```swift
/// if let path = BinaryLocator.which("claude") {
///     print("Claude CLI found at: \(path)")
/// }
/// ```
public struct BinaryLocator: Sendable {
    public init() {}

    /// Finds a tool by name using the user's login shell PATH.
    ///
    /// - Parameter tool: The name of the CLI tool (e.g., "claude", "codex", "gemini")
    /// - Returns: The full path to the tool if found, nil otherwise
    public func locate(_ tool: String) -> String? {
        Self.which(tool)
    }

    /// Finds a tool by name using the user's login shell.
    ///
    /// Runs `which` through a login shell to access the user's full PATH,
    /// including paths from nix-darwin, Homebrew, and other package managers.
    ///
    /// - Parameter tool: The name of the CLI tool
    /// - Returns: The full path to the tool if found, nil otherwise
    public static func which(_ tool: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell (sources .zshrc/.bashrc), -c = run command
        proc.arguments = ["-l", "-c", "which \(tool)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }

    /// Gets the user's PATH from their login shell.
    ///
    /// - Returns: The full PATH string from the user's shell, or system PATH as fallback
    public static func shellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty else {
                return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
            }
            return path
        } catch {
            return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        }
    }
}