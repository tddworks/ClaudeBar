import Diagnostics
import Quotas
import Foundation

/// Seconds since Foundation's reference date; only durations are ever taken
/// from it.
private func nowSeconds() -> Double { Date.timeIntervalSinceReferenceDate }

/// Runs CLI commands in an interactive terminal session.
///
/// Many CLI tools (like Claude, Codex, Gemini) detect when they're not running in a
/// real terminal and change their behavior. This runner simulates a terminal session
/// so these tools produce their normal, parseable output. What a terminal is here —
/// the pty or pseudo console, starting the CLI in it, and what its session's
/// environment differs in — this platform's `PseudoTerminal` answers (MODULAR_DESIGN
/// §10); finding the CLI, the environment it starts with under the OS's name rule
/// and how long it is given to stop are the `InstalledPrograms` and `ChildLaunch`
/// facts. Everything else here is the same on every platform: the terminal defaults
/// a CLI gets, the screen's size, typing and reading.
///
/// Usage:
/// ```swift
/// let runner = InteractiveRunner(terminal: MacPty(), programs: MacProcesses())
/// let result = try runner.run(binary: "claude", input: "/usage")
/// print(result.output)
/// ```
public struct InteractiveRunner: Sendable {

    /// The terminal this session runs in.
    private let terminal: any PseudoTerminal
    /// Finds the CLI, starts it with its environment and gives it its time to
    /// stop, as this OS does any program.
    private let programs: any InstalledPrograms & ChildLaunch

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
        /// Environment variable keys to exclude from the subprocess environment.
        /// Use this to prevent env vars like `CLAUDE_CODE_OAUTH_TOKEN` from being
        /// inherited by the subprocess, forcing it to use stored credentials instead.
        public var environmentExclusions: [String]
        /// Environment variables to set on the subprocess, on top of the
        /// inherited environment. Applied after exclusions and after the
        /// terminal defaults, so additions always win. Fetches mark their
        /// sessions with `CLAUDEBAR_PROBE=1` so ClaudeBar's installed hook
        /// command can recognize and skip them (issue #222).
        public var environmentAdditions: [String: String]
        /// Optional rule that tells the runner when the screen has settled.
        /// Without it, any idle gap ends the capture — which truncates TUIs that
        /// paint a placeholder first and fill it in asynchronously (issue #271).
        public var completionRule: CLICompletionRule?
        /// How long to wait after launch before sending `input`.
        ///
        /// TUIs that redraw their input box during startup can swallow text
        /// typed while the first paint is still in flight. CLIs that are typed into
        /// a TUI raise this so the command lands on a settled screen.
        public var inputDelay: TimeInterval
        /// Quality of service for the spawned process tree.
        ///
        /// Defaults to the ambient `FetchContext` value. Because default
        /// arguments are evaluated at the call site, constructing `Options` inside
        /// the monitor's `.utility` scope captures `.utility` — `run()` itself may
        /// then execute on a plain thread without losing the task local (issue #204).
        public var qualityOfService: QualityOfService

        public init(
            timeout: TimeInterval = 20.0,
            workingDirectory: URL? = nil,
            arguments: [String] = [],
            autoResponses: [String: String] = [:],
            environmentExclusions: [String] = [],
            environmentAdditions: [String: String] = [:],
            completionRule: CLICompletionRule? = nil,
            inputDelay: TimeInterval = 0.4,
            qualityOfService: QualityOfService = FetchContext.qualityOfService
        ) {
            self.timeout = timeout
            self.workingDirectory = workingDirectory
            self.arguments = arguments
            self.autoResponses = autoResponses
            self.environmentExclusions = environmentExclusions
            self.environmentAdditions = environmentAdditions
            self.completionRule = completionRule
            self.inputDelay = inputDelay
            self.qualityOfService = qualityOfService
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

    init(terminal: any PseudoTerminal, programs: any InstalledPrograms & ChildLaunch) {
        self.terminal = terminal
        self.programs = programs
    }

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
        let totalStart = nowSeconds()

        let findStart = nowSeconds()
        let executablePath = try findExecutable(binary)
        let findElapsed = nowSeconds() - findStart
        AppLog.probes.debug("InteractiveRunner: findExecutable('\(binary)') took \(String(format: "%.3f", findElapsed))s")

        let runStart = nowSeconds()
        let session = try start(executablePath, options: options)
        defer { session.end() }

        // Allow the process to initialize; `inputDelay` gives TUIs time to finish
        // their startup paint before typed input lands (see Options.inputDelay).
        Thread.sleep(forTimeInterval: max(0, options.inputDelay))

        // Send the input command
        try sendInput(input, to: session)

        // Read output, handling any prompts automatically
        let buffer = captureOutput(from: session, options: options)
        let runElapsed = nowSeconds() - runStart
        AppLog.probes.debug("InteractiveRunner: process execution took \(String(format: "%.3f", runElapsed))s")

        guard let text = String(data: buffer, encoding: .utf8), !text.isEmpty else {
            throw RunError.timedOut
        }

        let totalElapsed = nowSeconds() - totalStart
        AppLog.probes.debug("InteractiveRunner: total run() took \(String(format: "%.3f", totalElapsed))s for '\(binary)'")

        return Result(output: text, exitCode: session.exitCode ?? -1)
    }

    // MARK: - Private Helpers

    /// Finds the full path to a CLI tool.
    private func findExecutable(_ binary: String) throws -> String {
        if FileManager.default.isExecutableFile(atPath: binary) {
            return binary
        }
        if let found = programs.find(binary) {
            return found
        }
        throw RunError.binaryNotFound(binary)
    }

    /// Starts the CLI in a new terminal, in its session's environment.
    private func start(_ executablePath: String, options: Options) throws -> any TerminalSession {
        let launch = TerminalLaunch(
            executable: executablePath,
            arguments: options.arguments,
            environment: programs.environment(for: executablePath, sessionChange(options)),
            directory: options.workingDirectory,
            rows: UInt16(TerminalRenderer.rows),
            cols: UInt16(TerminalRenderer.cols),
            // Carry the fetch QoS captured when `Options` was built: the
            // background monitoring loop binds `.utility` (issue #204).
            qualityOfService: options.qualityOfService,
            stopGrace: programs.stopGrace
        )
        do {
            return try terminal.start(launch)
        } catch PseudoTerminalError.couldNotOpen {
            throw RunError.launchFailed("Could not create terminal session")
        } catch PseudoTerminalError.couldNotStart(let reason) {
            throw RunError.launchFailed(reason)
        }
    }

    /// What a session changes in the environment a program starts with,
    /// handed to `ChildLaunch` as one change it applies under its OS's name
    /// rule: the call's exclusions removed; the terminal defaults every CLI
    /// gets where the app has none; and set over both, this OS's terminal
    /// `PATH`, then the call's additions, so they win.
    private func sessionChange(_ options: Options) -> ProcessEnvironment {
        var defaults = ["HOME": NSHomeDirectory(), "TERM": "xterm-256color", "COLORTERM": "truecolor", "CI": "0"]
        defaults["LANG"] = terminal.fallbackLocale
        var set: [String: String] = [:]
        set["PATH"] = terminal.sessionPath()
        set.merge(options.environmentAdditions) { _, addition in addition }
        return ProcessEnvironment(unset: options.environmentExclusions, defaults: defaults, set: set)
    }

    /// Sends input text to the running command.
    private func sendInput(_ input: String, to session: any TerminalSession) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let data = (trimmed + "\r").data(using: .utf8) else { return }
        try session.write(data)
    }

    /// Captures output from the command, automatically responding to known prompts.
    private func captureOutput(from session: any TerminalSession, options: Options) -> Data {
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
            buffer.append(session.read())

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
                    try? session.write(item.response)
                    respondedPrompts.insert(item.prompt)
                    lastMeaningfulDataTime = Date()  // Reset idle timer after responding
                }
            }

            // Exit if process stopped
            if !session.isRunning { break }

            // Exit if we have meaningful output and no new meaningful data for
            // idleTimeout — unless the screen says it is still filling in, in
            // which case idle means "waiting on the network", not "done".
            if hasMeaningfulContent(buffer),
               Date().timeIntervalSince(lastMeaningfulDataTime) > idleTimeout,
               !isAwaitingCompletion(buffer, rule: options.completionRule) {
                break
            }

            Thread.sleep(forTimeInterval: 0.06)
        }

        // Capture any remaining output
        buffer.append(session.read())
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
    /// Whether the captured screen is still filling in under `rule`.
    /// Returns false when there is no rule, so runs without one are unchanged.
    internal func isAwaitingCompletion(_ data: Data, rule: CLICompletionRule?) -> Bool {
        guard let rule, let text = String(data: data, encoding: .utf8) else { return false }
        return rule.isPending(text)
    }

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

}
