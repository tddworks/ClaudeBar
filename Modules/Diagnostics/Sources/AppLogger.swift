import Foundation
import OSLog

/// Dual-output logger that writes to both OSLog (for developers) and file (for users).
///
/// This facade provides category-specific loggers that output to:
/// 1. **OSLog** - For Console.app, live streaming, and development debugging
/// 2. **File** - For user-accessible logs at ~/Library/Logs/ClaudeBar/ClaudeBar.log
///
/// ## Usage Examples
///
/// ```swift
/// // Monitor operations
/// AppLog.monitor.info("Starting refresh for \(providers.count) providers")
///
/// // Probe execution
/// AppLog.probes.debug("Executing Claude CLI probe")
/// AppLog.probes.error("CLI probe failed: \(error.localizedDescription)")
///
/// // Sensitive data - use sanitized messages for file logs
/// AppLog.credentials.info("Token loaded for provider")
/// ```
///
/// ## Log Levels
///
/// | Level | File Output | OSLog Persistence |
/// |-------|-------------|-------------------|
/// | debug | No | Memory only |
/// | info | Yes | With `log collect` |
/// | warning | Yes | Always persisted |
/// | error | Yes | Always persisted |
///
/// ## Viewing Logs
///
/// **File logs (for users):**
/// ```
/// ~/Library/Logs/ClaudeBar/ClaudeBar.log
/// ```
///
/// **OSLog (for developers):**
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
    
    /// Open the logs directory in Finder
    public static func openLogsDirectory() {
        FileLogger.shared.openLogsDirectory()
    }
    
    /// The URL to the logs directory
    public static var logsDirectoryURL: URL {
        FileLogger.shared.logsDirectory
    }
}

/// A category-specific logger that outputs to both OSLog and file.
///
/// **Privacy Note**: All messages are logged publicly (no redaction).
/// Callers must manually redact sensitive data before logging.
/// Do NOT log tokens, API keys, passwords, or other secrets.
public struct CategoryLogger: Sendable {
    private let category: String
    private let osLogger: Logger
    
    init(category: String) {
        self.category = category
        let subsystem = Bundle.main.bundleIdentifier ?? "com.tddworks.ClaudeBar"
        self.osLogger = Logger(subsystem: subsystem, category: category)
    }
    
    /// Log a debug message (OSLog only, not written to file).
    /// - Note: Message is logged publicly. Caller must redact sensitive data.
    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }
    
    /// Log an info message (written to both OSLog and file).
    /// - Note: Message is logged publicly. Caller must redact sensitive data.
    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        FileLogger.shared.log(.info, category: category, message: message)
    }
    
    /// Log a notice message (written to both OSLog and file as INFO level).
    /// - Note: Message is logged publicly. Caller must redact sensitive data.
    public func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        FileLogger.shared.log(.info, category: category, message: message)
    }
    
    /// Log a warning message (written to both OSLog and file).
    /// - Note: Message is logged publicly. Caller must redact sensitive data.
    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        FileLogger.shared.log(.warning, category: category, message: message)
    }
    
    /// Log an error message (written to both OSLog and file).
    /// - Note: Message is logged publicly. Caller must redact sensitive data.
    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        FileLogger.shared.log(.error, category: category, message: message)
    }
}


