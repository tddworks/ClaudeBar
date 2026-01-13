import Foundation

/// Finds where CLI tools are installed on the system.
///
/// Uses the user's login shell to run `which`, ensuring access to the full PATH
/// from their shell configuration (.zshrc, .bashrc, config.nu, etc.). This supports
/// tools installed via nix-darwin, Homebrew, npm, and other package managers.
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
        let startTime = CFAbsoluteTimeGetCurrent()
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = Shell.detect(from: shellPath)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shellPath)
        proc.arguments = shell.whichArguments(for: tool)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.which('\(tool)') took \(String(format: "%.3f", elapsed))s")
            guard proc.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            return shell.parseWhichOutput(output)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.which('\(tool)') failed after \(String(format: "%.3f", elapsed))s")
            return nil
        }
    }

    /// Gets the user's PATH from their login shell.
    ///
    /// - Returns: The full PATH string from the user's shell, or system PATH as fallback
    public static func shellPath() -> String {
        let startTime = CFAbsoluteTimeGetCurrent()
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shell = Shell.detect(from: shellPath)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shellPath)
        proc.arguments = shell.pathArguments()

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        let fallback = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"

        do {
            try proc.run()
            proc.waitUntilExit()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.shellPath() took \(String(format: "%.3f", elapsed))s")
            guard proc.terminationStatus == 0 else { return fallback }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return fallback }

            let path = shell.parsePathOutput(output)
            return path.isEmpty ? fallback : path
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.shellPath() failed after \(String(format: "%.3f", elapsed))s")
            return fallback
        }
    }
}
