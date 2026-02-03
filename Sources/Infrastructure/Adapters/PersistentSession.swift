import Darwin
import Foundation

/// A long-lived PTY session for interactive CLI tools.
///
/// Unlike `InteractiveRunner` which spawns a new process for each command,
/// `PersistentSession` keeps a single session alive and sends multiple commands
/// to it. This is useful for tools like Claude CLI that have significant startup
/// overhead (trust prompts, initialization, etc.).
///
/// Usage:
/// ```swift
/// let session = PersistentSession(binary: "claude")
/// try await session.start()
///
/// // First command - waits for CLI to be ready
/// let usage1 = try await session.sendCommand("/usage")
///
/// // Subsequent commands are faster - no startup overhead
/// let usage2 = try await session.sendCommand("/usage")
///
/// session.stop()
/// ```
public actor PersistentSession {

    /// Errors that can occur with the session.
    public enum SessionError: Error, LocalizedError {
        case binaryNotFound(String)
        case launchFailed(String)
        case sessionNotStarted
        case sessionDied
        case timedOut
        case invalidOutput

        public var errorDescription: String? {
            switch self {
            case let .binaryNotFound(tool):
                "CLI '\(tool)' not found. Please install it and ensure it's on PATH."
            case let .launchFailed(reason):
                "Failed to start session: \(reason)"
            case .sessionNotStarted:
                "Session has not been started. Call start() first."
            case .sessionDied:
                "Session process has terminated unexpectedly."
            case .timedOut:
                "Command did not complete within the timeout."
            case .invalidOutput:
                "Could not decode output from session."
            }
        }
    }

    /// Configuration for the session.
    public struct Config: Sendable {
        /// The CLI binary to run.
        public let binary: String
        /// Arguments to pass when starting the CLI.
        public let arguments: [String]
        /// Working directory for the CLI.
        public let workingDirectory: URL?
        /// Automatic responses to prompts during startup.
        public let autoResponses: [String: String]
        /// Timeout for commands.
        public let commandTimeout: TimeInterval
        /// Timeout for waiting for the CLI to be ready after startup.
        public let startupTimeout: TimeInterval

        public init(
            binary: String,
            arguments: [String] = [],
            workingDirectory: URL? = nil,
            autoResponses: [String: String] = [:],
            commandTimeout: TimeInterval = 15.0,
            startupTimeout: TimeInterval = 30.0
        ) {
            self.binary = binary
            self.arguments = arguments
            self.workingDirectory = workingDirectory
            self.autoResponses = autoResponses
            self.commandTimeout = commandTimeout
            self.startupTimeout = startupTimeout
        }
    }

    // Terminal size
    private static let terminalRows: UInt16 = 50
    private static let terminalCols: UInt16 = 160

    private let config: Config
    private var process: Process?
    private var primaryFD: Int32 = -1
    private var primaryHandle: FileHandle?
    private var isStarted = false

    /// Marker text we look for to know the CLI is ready for input.
    /// Claude CLI shows "❯" when ready for a command.
    private let readyMarker = "❯"

    public init(config: Config) {
        self.config = config
    }

    /// Whether the session is currently running.
    public var isRunning: Bool {
        guard let process else { return false }
        return process.isRunning
    }

    /// Starts the session and waits for the CLI to be ready.
    public func start() async throws {
        if isStarted && isRunning {
            AppLog.probes.debug("PersistentSession: already running")
            return
        }

        AppLog.probes.info("PersistentSession: starting \(config.binary)...")

        // Find the executable
        guard let executablePath = BinaryLocator.which(config.binary) else {
            throw SessionError.binaryNotFound(config.binary)
        }

        // Open PTY
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var terminalSize = winsize(
            ws_row: Self.terminalRows,
            ws_col: Self.terminalCols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &terminalSize) == 0 else {
            throw SessionError.launchFailed("Could not create terminal session")
        }

        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = config.arguments
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle
        process.environment = Self.terminalEnvironment()

        if let workingDirectory = config.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        // Start the process
        do {
            try process.run()
        } catch {
            try? primaryHandle.close()
            try? secondaryHandle.close()
            throw SessionError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.primaryFD = primaryFD
        self.primaryHandle = primaryHandle
        self.isStarted = true

        // Wait for CLI to be ready (show prompt)
        AppLog.probes.debug("PersistentSession: waiting for CLI to be ready...")
        try await waitForReady(handle: primaryHandle)
        AppLog.probes.info("PersistentSession: CLI is ready")
    }

    /// Sends a command to the session and returns the output.
    public func sendCommand(_ command: String, timeout: TimeInterval? = nil) async throws -> String {
        guard isStarted else {
            throw SessionError.sessionNotStarted
        }
        guard let process, process.isRunning else {
            throw SessionError.sessionDied
        }
        guard let primaryHandle else {
            throw SessionError.sessionNotStarted
        }

        let effectiveTimeout = timeout ?? config.commandTimeout
        AppLog.probes.debug("PersistentSession: sending command '\(command)'")

        // Clear any pending output first
        _ = readAvailableData()

        // For slash commands, type slowly to let autocomplete process
        if command.hasPrefix("/") {
            // Type the command character by character
            for char in command {
                try primaryHandle.write(contentsOf: String(char).data(using: .utf8)!)
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms between chars
            }
            // Wait for autocomplete menu to fully render
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            // Press Enter to execute the slash command
            try primaryHandle.write(contentsOf: "\r".data(using: .utf8)!)
            AppLog.probes.debug("PersistentSession: sent Enter after slash command")
        } else {
            // Regular command - send all at once
            let commandData = (command + "\r").data(using: .utf8)!
            try primaryHandle.write(contentsOf: commandData)
        }

        // Wait for output and next prompt
        let output = try await captureCommandOutput(timeout: effectiveTimeout)
        AppLog.probes.debug("PersistentSession: received \(output.count) chars")

        return output
    }

    /// Stops the session.
    public func stop() {
        AppLog.probes.info("PersistentSession: stopping...")

        if let primaryHandle {
            try? primaryHandle.close()
        }

        if let process, process.isRunning {
            process.terminate()
            // Give it a moment to terminate gracefully
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < deadline {
                usleep(100_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        self.process = nil
        self.primaryHandle = nil
        self.primaryFD = -1
        self.isStarted = false
    }

    // MARK: - Private Helpers

    /// Waits for the CLI to show its ready prompt.
    private func waitForReady(handle: FileHandle) async throws {
        let deadline = Date().addingTimeInterval(config.startupTimeout)
        var buffer = Data()
        var respondedPrompts = Set<String>()

        while Date() < deadline {
            // Read available data
            let newData = readAvailableData()
            if !newData.isEmpty {
                buffer.append(newData)

                // Check for auto-response prompts
                if let text = String(data: buffer, encoding: .utf8) {
                    for (prompt, response) in config.autoResponses {
                        if text.contains(prompt) && !respondedPrompts.contains(prompt) {
                            AppLog.probes.debug("PersistentSession: auto-responding to '\(prompt)'")
                            if let responseData = response.data(using: .utf8) {
                                try? handle.write(contentsOf: responseData)
                            }
                            respondedPrompts.insert(prompt)
                        }
                    }

                    // Check if CLI is ready
                    if text.contains(readyMarker) {
                        return
                    }
                }
            }

            // Small delay to avoid busy-waiting
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        throw SessionError.timedOut
    }

    /// Captures output from a command until the next prompt appears.
    private func captureCommandOutput(timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var lastDataTime = Date()
        let idleTimeout: TimeInterval = 5.0  // Wait longer for TUI to render
        let minContentLength = 500  // Expect at least this much content for /usage

        while Date() < deadline {
            let newData = readAvailableData()
            if !newData.isEmpty {
                buffer.append(newData)
                lastDataTime = Date()

                // Check if we have enough content and see the prompt again
                if let text = String(data: buffer, encoding: .utf8) {
                    // Look for usage-related content (% used/left)
                    let hasUsageContent = text.contains("% used") || text.contains("% left") ||
                                          text.contains("Current session") || text.contains("Total cost")

                    // If we have usage content and see the prompt, we're done
                    if hasUsageContent {
                        let lines = text.components(separatedBy: .newlines)
                        if lines.count > 5 {
                            // Check last few lines for prompt or idle
                            let lastLines = lines.suffix(5).joined()
                            if lastLines.contains(readyMarker) || lastLines.contains("escape to cancel") {
                                return text
                            }
                        }
                    }
                }
            }

            // Exit if no new data for idleTimeout and we have meaningful content
            let textSoFar = String(data: buffer, encoding: .utf8) ?? ""
            let hasMeaningfulContent = textSoFar.contains("% used") || textSoFar.contains("% left") ||
                                       textSoFar.contains("Current session") || textSoFar.contains("Total cost")
            if hasMeaningfulContent && Date().timeIntervalSince(lastDataTime) > idleTimeout {
                break
            }

            // Also exit if buffer is large enough and idle
            if buffer.count > minContentLength && Date().timeIntervalSince(lastDataTime) > idleTimeout {
                break
            }

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        guard let output = String(data: buffer, encoding: .utf8) else {
            throw SessionError.invalidOutput
        }

        return output
    }

    /// Reads all available data from the PTY.
    private func readAvailableData() -> Data {
        guard primaryFD >= 0 else { return Data() }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)

        while true {
            let bytesRead = Darwin.read(primaryFD, &chunk, chunk.count)
            if bytesRead > 0 {
                buffer.append(contentsOf: chunk.prefix(bytesRead))
            } else {
                break
            }
        }

        return buffer
    }

    /// Environment variables for the terminal session.
    private static func terminalEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = BinaryLocator.shellPath()
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["CI"] = env["CI"] ?? "0"
        return env
    }
}
