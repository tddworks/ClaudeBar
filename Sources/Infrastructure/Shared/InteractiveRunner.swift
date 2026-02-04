import Darwin
import Foundation

/// Runs CLI commands in an interactive terminal session.
///
/// Many CLI tools (like Claude, Codex, Gemini) detect when they're not running in a
/// real terminal and change their behavior. This runner simulates a terminal session
/// so these tools produce their normal, parseable output.
///
/// Usage:
/// ```swift
/// let runner = InteractiveRunner()
/// let result = try runner.run(binary: "claude", input: "/usage")
/// print(result.output)
/// ```
public struct InteractiveRunner: Sendable {

    /// The result of running a command.
    public struct Result: Sendable {
        /// The captured output from the command.
        public let output: String
        /// The command's exit code (0 typically means success).
        public let exitCode: Int32
    }

    /// Configuration for running a command.
    public struct Options: Sendable {
        /// Maximum time to wait for the command to complete.
        public var timeout: TimeInterval
        /// Directory to run the command in (uses current directory if nil).
        public var workingDirectory: URL?
        /// Arguments to pass to the command.
        public var arguments: [String]
        /// Automatic responses to prompts. Maps prompt text to the response to send.
        /// Example: `["Continue? [y/n]": "y\r"]` will auto-respond "y" when prompted.
        public var autoResponses: [String: String]

        public init(
            timeout: TimeInterval = 20.0,
            workingDirectory: URL? = nil,
            arguments: [String] = [],
            autoResponses: [String: String] = [:]
        ) {
            self.timeout = timeout
            self.workingDirectory = workingDirectory
            self.arguments = arguments
            self.autoResponses = autoResponses
        }
    }

    /// Errors that can occur when running a command.
    public enum RunError: Error, LocalizedError, Sendable {
        /// The CLI tool was not found on the system.
        case binaryNotFound(String)
        /// The command failed to start.
        case launchFailed(String)
        /// The command did not complete within the timeout.
        case timedOut

        public var errorDescription: String? {
            switch self {
            case let .binaryNotFound(tool):
                "CLI '\(tool)' not found. Please install it and ensure it's on PATH."
            case let .launchFailed(reason):
                "Failed to start command: \(reason)"
            case .timedOut:
                "Command did not complete within the timeout."
            }
        }
    }

    // Terminal size for the simulated session
    private static let terminalRows: UInt16 = 50
    private static let terminalCols: UInt16 = 160

    public init() {}

    /// Runs a command and captures its output.
    ///
    /// - Parameters:
    ///   - binary: The CLI tool to run (e.g., "claude", "codex")
    ///   - input: Text to send to the command (e.g., "/usage")
    ///   - options: Configuration for timeout, arguments, and auto-responses
    /// - Returns: The captured output and exit code
    /// - Throws: `RunError` if the tool is not found, fails to start, or times out
    public func run(
        binary: String,
        input: String,
        options: Options = Options()
    ) throws -> Result {
        let totalStart = CFAbsoluteTimeGetCurrent()

        let findStart = CFAbsoluteTimeGetCurrent()
        let executablePath = try findExecutable(binary)
        let findElapsed = CFAbsoluteTimeGetCurrent() - findStart
        AppLog.probes.debug("InteractiveRunner: findExecutable('\(binary)') took \(String(format: "%.3f", findElapsed))s")

        let (primaryFD, secondaryFD) = try openTerminal()

        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        let process = createProcess(
            executablePath: executablePath,
            options: options,
            terminalHandle: secondaryHandle
        )

        var cleanedUp = false
        var didLaunch = false

        func cleanup() {
            guard !cleanedUp else { return }
            cleanedUp = true

            try? primaryHandle.close()
            try? secondaryHandle.close()

            if didLaunch, process.isRunning {
                process.terminate()
                let waitDeadline = Date().addingTimeInterval(2.0)
                while process.isRunning, Date() < waitDeadline {
                    usleep(100_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
            }
        }

        defer { cleanup() }

        let runStart = CFAbsoluteTimeGetCurrent()
        try process.run()
        didLaunch = true

        // Allow process to initialize
        usleep(400_000)

        // Send the input command
        try sendInput(input, to: primaryHandle)

        // Read output, handling any prompts automatically
        let buffer = try captureOutput(
            from: primaryFD,
            handle: primaryHandle,
            process: process,
            options: options
        )
        let runElapsed = CFAbsoluteTimeGetCurrent() - runStart
        AppLog.probes.debug("InteractiveRunner: process execution took \(String(format: "%.3f", runElapsed))s")

        guard let text = String(data: buffer, encoding: .utf8), !text.isEmpty else {
            throw RunError.timedOut
        }

        let totalElapsed = CFAbsoluteTimeGetCurrent() - totalStart
        AppLog.probes.debug("InteractiveRunner: total run() took \(String(format: "%.3f", totalElapsed))s for '\(binary)'")

        let exitCode: Int32 = process.isRunning ? -1 : process.terminationStatus
        return Result(output: text, exitCode: exitCode)
    }

    // MARK: - Private Helpers

    /// Finds the full path to a CLI tool.
    private func findExecutable(_ binary: String) throws -> String {
        if FileManager.default.isExecutableFile(atPath: binary) {
            return binary
        }
        if let found = BinaryLocator.which(binary) {
            return found
        }
        throw RunError.binaryNotFound(binary)
    }

    /// Opens a pseudo-terminal for the interactive session.
    private func openTerminal() throws -> (primary: Int32, secondary: Int32) {
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var terminalSize = winsize(
            ws_row: Self.terminalRows,
            ws_col: Self.terminalCols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &terminalSize) == 0 else {
            throw RunError.launchFailed("Could not create terminal session")
        }
        return (primaryFD, secondaryFD)
    }

    /// Creates and configures the process to run.
    private func createProcess(
        executablePath: String,
        options: Options,
        terminalHandle: FileHandle
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = options.arguments
        process.standardInput = terminalHandle
        process.standardOutput = terminalHandle
        process.standardError = terminalHandle
        process.environment = Self.terminalEnvironment()

        if let workingDirectory = options.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        return process
    }

    /// Sends input text to the running command.
    private func sendInput(_ input: String, to handle: FileHandle) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let data = (trimmed + "\r").data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }

    /// Captures output from the command, automatically responding to known prompts.
    private func captureOutput(
        from fd: Int32,
        handle: FileHandle,
        process: Process,
        options: Options
    ) throws -> Data {
        let deadline = Date().addingTimeInterval(options.timeout)
        var buffer = Data()
        var lastMeaningfulDataTime = Date()
        let idleTimeout: TimeInterval = 3.0  // Exit if no new meaningful data for 3 seconds

        let promptResponses = options.autoResponses.map {
            (prompt: Data($0.key.utf8), response: Data($0.value.utf8))
        }
        var respondedPrompts = Set<Data>()

        while Date() < deadline {
            let previousSize = buffer.count
            readAvailableData(from: fd, into: &buffer)

            // Track when we last received MEANINGFUL data (not just OSC/escape sequences)
            if buffer.count > previousSize {
                let newData = buffer.suffix(from: previousSize)
                if isMeaningfulData(newData) {
                    lastMeaningfulDataTime = Date()
                }
            }

            // Auto-respond to any recognized prompts
            for item in promptResponses where !respondedPrompts.contains(item.prompt) {
                if buffer.range(of: item.prompt) != nil {
                    try? handle.write(contentsOf: item.response)
                    respondedPrompts.insert(item.prompt)
                    lastMeaningfulDataTime = Date()  // Reset idle timer after responding
                }
            }

            // Exit if process stopped
            if !process.isRunning { break }

            // Exit if we have meaningful output and no new meaningful data for idleTimeout
            if hasMeaningfulContent(buffer) && Date().timeIntervalSince(lastMeaningfulDataTime) > idleTimeout {
                break
            }

            usleep(60000)
        }

        // Capture any remaining output
        readAvailableData(from: fd, into: &buffer)
        return buffer
    }

    /// Checks if newly received data is meaningful (not just OSC/title sequences).
    /// OSC sequences like `ESC ] 0 ; title BEL` are used for terminal title updates
    /// and should not reset the idle timer.
    private func isMeaningfulData(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            return !data.isEmpty  // Non-UTF8 binary data is considered meaningful
        }

        // Strip OSC sequences (terminal title updates like "✶ Claude Code")
        // OSC format: ESC ] ... BEL  or  ESC ] ... ESC \
        var stripped = text
        if let oscRegex = Self.oscRegex {
            stripped = oscRegex.stringByReplacingMatches(
                in: stripped,
                range: NSRange(stripped.startIndex..., in: stripped),
                withTemplate: ""
            )
        }

        // Strip other non-printing control sequences
        stripped = stripped.replacingOccurrences(of: "\u{1B}", with: "")
        stripped = stripped.replacingOccurrences(of: "\u{07}", with: "")  // BEL

        // Check if anything meaningful remains
        let meaningful = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return !meaningful.isEmpty
    }
    
    // MARK: - ANSI Escape Sequence Handling
    
    /// Cached regex for OSC sequences (ESC ] ... BEL or ESC ] ... ST).
    /// OSC = Operating System Command, used for terminal titles, hyperlinks, etc.
    /// Matches: ESC ] followed by any content (non-greedy) terminated by BEL (0x07) or ST (ESC \)
    private static let oscRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\x1B\].*?(?:\x07|\x1B\\)"#,
            options: .dotMatchesLineSeparators
        )
    }()
    
    /// Checks if buffer contains meaningful content beyond just ANSI escape sequences.
    ///
    /// ANSI escape sequences stripped:
    /// - **CSI** (Control Sequence Introducer): `ESC [` followed by parameters and a letter
    ///   - Examples: `\x1B[0m` (reset), `\x1B[?25h` (show cursor)
    /// - **Charset**: `ESC (` or `ESC )` followed by charset designator
    ///   - Examples: `\x1B(B` (ASCII), `\x1B(0` (line drawing)
    /// - **OSC** (Operating System Command): `ESC ]` ... terminated by BEL or ST
    ///   - BEL termination: `\x1B]0;title\x07`
    ///   - ST termination: `\x1B]0;title\x1B\\`
    ///
    /// - Parameter data: The raw data buffer to check
    /// - Returns: `true` if visible text content remains after stripping escapes,
    ///            `true` if data is non-UTF8 (binary data), `false` otherwise
    internal func hasMeaningfulContent(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else {
            // Non-UTF8 binary data is considered meaningful
            return !data.isEmpty
        }
        
        // Strip CSI sequences: ESC[ followed by parameters and final byte
        var stripped = text.replacingOccurrences(
            of: #"\x1B\[[0-9;?]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
        
        // Strip charset designation sequences: ESC( or ESC) followed by charset
        stripped = stripped.replacingOccurrences(
            of: #"\x1B[\(\)][AB012]"#,
            with: "",
            options: .regularExpression
        )
        
        // Strip OSC sequences using cached regex
        if let oscRegex = Self.oscRegex {
            stripped = oscRegex.stringByReplacingMatches(
                in: stripped,
                range: NSRange(stripped.startIndex..., in: stripped),
                withTemplate: ""
            )
        }
        
        // Strip remaining lone ESC characters
        stripped = stripped.replacingOccurrences(of: "\u{1B}", with: "")
        
        // Check if anything meaningful remains after stripping whitespace
        let meaningful = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return !meaningful.isEmpty
    }

    /// Reads all currently available data from a file descriptor.
    private func readAvailableData(from fd: Int32, into buffer: inout Data) {
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let bytesRead = Darwin.read(fd, &chunk, chunk.count)
            if bytesRead > 0 {
                buffer.append(contentsOf: chunk.prefix(bytesRead))
            } else {
                break
            }
        }
    }

    /// Environment variables for the terminal session.
    /// Ensures CLI tools behave as they would in a normal terminal.
    private static func terminalEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ensureCommonPathsIncluded(BinaryLocator.shellPath())
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        env["COLORTERM"] = env["COLORTERM"] ?? "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["CI"] = env["CI"] ?? "0"
        return env
    }

    /// Ensures common tool paths are included in PATH.
    ///
    /// When apps are launched from Finder/launchd, the PATH obtained from login shell
    /// may not include paths configured in .zshrc/.bashrc (which are only loaded for
    /// interactive shells). This ensures common installation paths are always available.
    private static func ensureCommonPathsIncluded(_ path: String) -> String {
        let essentialPaths = [
            "/opt/homebrew/bin",  // Homebrew on Apple Silicon
            "/opt/homebrew/sbin",
            "/usr/local/bin",     // Homebrew on Intel / common tools
            "/usr/local/sbin",
        ]

        var components = path.split(separator: ":").map(String.init)
        let fm = FileManager.default

        for essentialPath in essentialPaths.reversed() {
            if !components.contains(essentialPath) && fm.fileExists(atPath: essentialPath) {
                components.insert(essentialPath, at: 0)
            }
        }

        return components.joined(separator: ":")
    }
}