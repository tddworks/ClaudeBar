import ClaudeBarKit
import Foundation

// AppLog is Kotlin (diagnostics); Swift keeps writing `AppLog.monitor.info("…")`.

extension AppLog: @retroactive @unchecked Sendable {}
extension CategoryLogger: @retroactive @unchecked Sendable {}

extension AppLog {
    public static var monitor: CategoryLogger { AppLog.shared.monitorLogger }
    public static var providers: CategoryLogger { AppLog.shared.providersLogger }
    public static var probes: CategoryLogger { AppLog.shared.probesLogger }
    public static var network: CategoryLogger { AppLog.shared.networkLogger }
    public static var credentials: CategoryLogger { AppLog.shared.credentialsLogger }
    public static var ui: CategoryLogger { AppLog.shared.uiLogger }
    public static var notifications: CategoryLogger { AppLog.shared.notificationsLogger }
    public static var updates: CategoryLogger { AppLog.shared.updatesLogger }
    public static var hooks: CategoryLogger { AppLog.shared.hooksLogger }

    /// `~/Library/Logs/ClaudeBar`.
    public static var logsDirectoryURL: URL { URL(fileURLWithPath: AppLog.shared.logsDirectory, isDirectory: true) }

    /// `~/Library/Logs/ClaudeBar/ClaudeBar.log`.
    public static var logFileURL: URL { logsDirectoryURL.appendingPathComponent("ClaudeBar.log") }
}

extension CategoryLogger {
    /// Unified log only. Messages are logged as given: never a token, key, cookie or credential.
    public func debug(_ message: String) { debug(message: message) }
    /// Unified log and the user's file.
    public func info(_ message: String) { info(message: message) }
    public func notice(_ message: String) { notice(message: message) }
    public func warning(_ message: String) { warning(message: message) }
    public func error(_ message: String) { error(message: message) }
}
