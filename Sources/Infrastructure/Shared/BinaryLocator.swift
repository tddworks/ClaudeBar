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
    static var commonPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            // User-local installations
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            // Bun global installs (e.g. `bun install -g @oh-my-pi/pi-coding-agent`)
            "\(home)/.bun/bin",
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
            // nvm (for node-based CLIs like codex)
            "\(home)/.nvm/versions",
            // Herd/nvm
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

    // MARK: - Caching

    /// Resolved tool paths. `nil` values are cached too, so a missing CLI does
    /// not re-spawn a login shell on every refresh.
    private static let toolCache = SingleFlightCache<String?>()

    /// The login shell's `PATH`, cached under a single fixed key.
    private static let shellPathCache = SingleFlightCache<String>()

    private static let shellPathCacheKey = "shellPath"

    /// A tool that was found stays cached for a while; the path is re-validated
    /// on read, so an uninstall is noticed immediately regardless of this value.
    private static let foundTTL: TimeInterval = 600

    /// A tool that was *not* found expires sooner, so installing a CLI while the
    /// app runs is picked up without a restart.
    private static let notFoundTTL: TimeInterval = 120

    private static let shellPathTTL: TimeInterval = 600

    /// Clears cached lookups so the next call re-resolves from the shell.
    /// Wired to manual refresh, where the user may have just installed a tool.
    public static func invalidateCaches() {
        toolCache.invalidateAll()
        shellPathCache.invalidateAll()
        AppLog.probes.debug("BinaryLocator: caches invalidated")
    }

    /// Finds a tool by name using the user's login shell.
    ///
    /// First tries to run `which` through a login shell to access the user's full PATH.
    /// If that fails (common in menu bar apps), falls back to checking common paths directly.
    ///
    /// Results are cached: this is called by every provider on every refresh, and
    /// each miss costs a login-shell spawn.
    ///
    /// - Parameter tool: The name of the CLI tool
    /// - Returns: The full path to the tool if found, nil otherwise
    public static func which(_ tool: String) -> String? {
        let cached = cachedResolve(tool)

        // A cached hit goes stale when the tool is upgraded or uninstalled
        // (version-pinned paths like nvm's move). Re-resolve rather than handing
        // back a path that no longer runs.
        if let cached, !FileManager.default.isExecutableFile(atPath: cached) {
            AppLog.probes.debug("BinaryLocator: cached path for '\(tool)' is stale, re-resolving")
            toolCache.invalidate(tool)
            return cachedResolve(tool)
        }

        return cached
    }

    private static func cachedResolve(_ tool: String) -> String? {
        toolCache.value(
            for: tool,
            ttl: { $0 == nil ? notFoundTTL : foundTTL },
            compute: { resolve(tool) }
        )
    }

    /// Uncached resolution: login shell first, then common install paths.
    private static func resolve(_ tool: String) -> String? {
        // An explicit path needs no lookup — and would never survive one, since
        // the shell-injection guard in `Shell.whichArguments` rejects `/`.
        // Callers legitimately pass already-resolved paths (a probe that located
        // its binary once, then executes it), which `InteractiveRunner` has
        // always accepted; accept them here too so both executors agree.
        if tool.contains("/"), FileManager.default.isExecutableFile(atPath: tool) {
            return tool
        }

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
            // Drain before waiting: reading only after `waitUntilExit()` deadlocks
            // if the child fills the pipe buffer while nothing consumes it.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.whichViaShell('\(tool)') took \(String(format: "%.3f", elapsed))s")
            guard proc.terminationStatus == 0 else { return nil }

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
    /// Cached: this runs inside `InteractiveRunner`'s environment setup, so an
    /// uncached call spawns a login shell for every probe of every provider.
    ///
    /// - Returns: The full PATH string from the user's shell, or system PATH as fallback
    public static func shellPath() -> String {
        shellPathCache.value(
            for: shellPathCacheKey,
            ttl: { _ in shellPathTTL },
            compute: { computeShellPath() }
        )
    }

    /// Uncached login-shell `PATH` lookup.
    private static func computeShellPath() -> String {
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
            // Drain before waiting, as above.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            AppLog.probes.debug("BinaryLocator.shellPath() took \(String(format: "%.3f", elapsed))s")
            guard proc.terminationStatus == 0 else { return fallback }

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
