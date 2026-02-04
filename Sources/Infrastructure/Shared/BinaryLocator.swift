import Foundation

/// Finds where CLI tools are installed on the system.
///
/// Uses the user's login shell to run `which`, ensuring access to the full PATH
/// from their shell configuration (.zshrc, .bashrc, config.nu, etc.). This supports
/// tools installed via nix-darwin, Homebrew, npm, and other package managers.
///
/// As a fallback (for sandboxed apps or limited launchd contexts), also checks
/// common installation paths directly.
///
/// Usage:
/// ```swift
/// if let path = BinaryLocator.which("claude") {
///     print("Claude CLI found at: \(path)")
/// }
/// ```
public struct BinaryLocator: Sendable {
    public init() {}

    /// Common paths where CLI tools are installed on macOS.
    /// These are checked as fallback when the shell `which` doesn't work
    /// (e.g., in menu bar apps launched by launchd with limited PATH).
    private static var commonPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            // User-local installations
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/bin",
            // Homebrew (Apple Silicon and Intel)
            "/opt/homebrew/bin",
            "/usr/local/bin",
            // Nix
            "\(home)/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/nix/var/nix/profiles/default/bin",
            // npm global (common locations)
            "\(home)/.npm-global/bin",
            "/usr/local/lib/node_modules/.bin",
            // pnpm
            "\(home)/Library/pnpm",
            // Herd/nvm (for node-based CLIs like codex)
            "\(home)/Library/Application Support/Herd/config/nvm/versions",
        ]
    }

    /// Finds a tool by name using the user's login shell PATH.
    ///
    /// - Parameter tool: The name of the CLI tool (e.g., "claude", "codex", "gemini")
    /// - Returns: The full path to the tool if found, nil otherwise
    public func locate(_ tool: String) -> String? {
        Self.which(tool)
    }

    /// Finds a tool by name using the user's login shell.
    ///
    /// First tries to run `which` through a login shell to access the user's full PATH.
    /// If that fails (common in menu bar apps), falls back to checking common paths directly.
    ///
    /// - Parameter tool: The name of the CLI tool
    /// - Returns: The full path to the tool if found, nil otherwise
    public static func which(_ tool: String) -> String? {
        // First, try using the login shell's `which`
        if let path = whichViaShell(tool) {
            return path
        }

        // Fallback: check common paths directly (for sandboxed/launchd contexts)
        return findInCommonPaths(tool)
    }

    /// Tries to find a tool using the user's login shell.
    private static func whichViaShell(_ tool: String) -> String? {
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
            AppLog.probes.debug("BinaryLocator.whichViaShell('\(tool)') took \(String(format: "%.3f", elapsed))s")
            guard proc.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            return shell.parseWhichOutput(output)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.whichViaShell('\(tool)') failed after \(String(format: "%.3f", elapsed))s")
            return nil
        }
    }

    /// Searches for a tool in common installation paths.
    /// This is the fallback for menu bar apps where shell access is limited.
    public static func findInCommonPaths(_ tool: String) -> String? {
        let fm = FileManager.default

        for basePath in commonPaths {
            // Direct check: /path/bin/tool
            let directPath = "\(basePath)/\(tool)"
            if fm.isExecutableFile(atPath: directPath) {
                AppLog.probes.debug("BinaryLocator.findInCommonPaths('\(tool)') found at \(directPath)")
                return directPath
            }

            // For nvm/Herd: search in version subdirectories
            // e.g., ~/Library/Application Support/Herd/config/nvm/versions/node/v24.11.0/bin/codex
            if basePath.contains("nvm/versions") || basePath.contains("Herd") {
                if let found = searchNvmVersions(basePath: basePath, tool: tool) {
                    return found
                }
            }
        }

        return nil
    }

    /// Searches for a tool in nvm/Herd version directories.
    /// Structure: basePath/node/vX.Y.Z/bin/tool
    private static func searchNvmVersions(basePath: String, tool: String) -> String? {
        let fm = FileManager.default
        let nodeVersionsPath = basePath.hasSuffix("/node") ? basePath : "\(basePath)/node"

        guard let versions = try? fm.contentsOfDirectory(atPath: nodeVersionsPath) else {
            return nil
        }

        // Sort versions descending to prefer newer versions
        let sortedVersions = versions.sorted { v1, v2 in
            v1.compare(v2, options: .numeric) == .orderedDescending
        }

        for version in sortedVersions {
            let binPath = "\(nodeVersionsPath)/\(version)/bin/\(tool)"
            if fm.isExecutableFile(atPath: binPath) {
                AppLog.probes.debug("BinaryLocator.searchNvmVersions('\(tool)') found at \(binPath)")
                return binPath
            }
        }

        return nil
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
