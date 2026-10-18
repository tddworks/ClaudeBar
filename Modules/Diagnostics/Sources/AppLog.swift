import Foundation

/// The app's log: one logger per category, each line sent to every `LogSink`
/// of the platform.
///
/// - **The file log**, on every platform, for people:
///   `~/Library/Logs/ClaudeBar/ClaudeBar.log` on the Mac,
///   `%LOCALAPPDATA%\ClaudeBar\Logs\ClaudeBar.log` on Windows. Every level
///   but `debug`; it rotates at 5 MB.
/// - **OSLog**, on the Mac, for developers: Console.app and `log show`, every level.
///
/// ```swift
/// AppLog.monitor.info("Starting refresh for \(providers.count) providers")
/// AppLog.probes.debug("Executing Claude CLI probe")
/// AppLog.probes.error("CLI probe failed: \(error.localizedDescription)")
/// ```
///
/// | Level | File | OSLog persistence |
/// |-------|------|-------------------|
/// | debug | No | Memory only |
/// | info, notice | Yes, as `INFO` | With `log collect` |
/// | warning | Yes | Always persisted |
/// | error | Yes | Always persisted |
///
/// OSLog, for developers:
/// ```bash
/// log show --predicate 'subsystem == "com.tddworks.ClaudeBar"' --info --debug --last 1h
/// ```
public enum AppLog {
    /// Logger for quota monitoring operations
    public static let monitor = CategoryLogger(category: "monitor")

    /// Logger for AI provider operations
    public static let providers = CategoryLogger(category: "providers")

    /// Logger for usage probe operations
    public static let probes = CategoryLogger(category: "probes")

    /// Logger for network operations
    public static let network = CategoryLogger(category: "network")

    /// Logger for credential operations
    public static let credentials = CategoryLogger(category: "credentials")

    /// Logger for UI operations
    public static let ui = CategoryLogger(category: "ui")

    /// Logger for notification operations
    public static let notifications = CategoryLogger(category: "notifications")

    /// Logger for update operations
    public static let updates = CategoryLogger(category: "updates")

    /// Logger for hook operations (Claude Code session tracking)
    public static let hooks = CategoryLogger(category: "hooks")

    /// The file log, which a person opens and attaches to an issue.
    public static let logFileURL: URL = {
        let files = FileManager.default
        #if os(macOS)
        let folder = files.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/ClaudeBar", directoryHint: .isDirectory)
        #else
        // %LOCALAPPDATA% on Windows, where Foundation has no Library folder.
        let folder = (files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? files.temporaryDirectory)
            .appending(path: "ClaudeBar/Logs", directoryHint: .isDirectory)
        #endif
        return folder.appending(path: "ClaudeBar.log")
    }()

    /// Where every line goes on this platform.
    static let sinks: [any LogSink] = {
        #if os(macOS)
        [OSLogSink(), FileLogSink(fileURL: logFileURL)]
        #else
        [FileLogSink(fileURL: logFileURL)]
        #endif
    }()
}

/// A category's logger: each line goes to every sink of the platform.
///
/// Registered secrets are scrubbed before a sink sees the line — the law
/// (a secret never appears in a log line) holds even when a caller forgets.
/// Callers still redact what they can: a line that never held a secret
/// needs no scrubbing.
public struct CategoryLogger: Sendable {
    private let category: String
    private let sinks: [any LogSink]

    init(category: String, sinks: [any LogSink] = AppLog.sinks) {
        self.category = category
        self.sinks = sinks
    }

    /// Log a debug message (OSLog only, not written to file).
    /// - Note: Registered secrets are scrubbed before the line is written.
    public func debug(_ message: String) {
        write(.debug, message)
    }

    /// Log an info message (written to both OSLog and file).
    /// - Note: Registered secrets are scrubbed before the line is written.
    public func info(_ message: String) {
        write(.info, message)
    }

    /// Log a notice message (written to both OSLog and file as INFO level).
    /// - Note: Registered secrets are scrubbed before the line is written.
    public func notice(_ message: String) {
        write(.notice, message)
    }

    /// Log a warning message (written to both OSLog and file).
    /// - Note: Registered secrets are scrubbed before the line is written.
    public func warning(_ message: String) {
        write(.warning, message)
    }

    /// Log an error message (written to both OSLog and file).
    /// - Note: Registered secrets are scrubbed before the line is written.
    public func error(_ message: String) {
        write(.error, message)
    }

    private func write(_ level: LogLevel, _ message: String) {
        let scrubbed = SecretRedactor.scrub(message)
        for sink in sinks {
            sink.write(level, category: category, message: scrubbed)
        }
    }
}
