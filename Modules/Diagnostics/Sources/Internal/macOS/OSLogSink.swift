#if os(macOS)
import Foundation
import OSLog
import Synchronization

/// Console.app's and `log show`'s view of the log, for developers: every
/// level, under the app's subsystem and the line's category.
final class OSLogSink: LogSink {
    private let subsystem: String
    /// One `Logger` per category, made on its first line.
    private let loggers = Mutex<[String: Logger]>([:])

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.tddworks.ClaudeBar") {
        self.subsystem = subsystem
    }

    func write(_ level: LogLevel, category: String, message: String) {
        let logger = loggers.withLock { loggers in
            if let logger = loggers[category] { return logger }
            let logger = Logger(subsystem: subsystem, category: category)
            loggers[category] = logger
            return logger
        }
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }
}
#endif
