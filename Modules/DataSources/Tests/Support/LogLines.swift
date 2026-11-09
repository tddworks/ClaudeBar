import Foundation
@testable import Diagnostics

/// What a logger wrote, each line with its level: a test hands
/// `LogLines().logger` to the code it runs and reads what a person's log would
/// hold, every level but `debug`.
final class LogLines: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [(level: LogLevel, message: String)] = []

    var logger: CategoryLogger { CategoryLogger(category: "test", sinks: [self]) }

    /// The lines the file log keeps: every level but `debug`.
    var inTheFile: [String] {
        lock.withLock { lines.filter { $0.level != .debug }.map(\.message) }
    }

    /// The lines written as errors.
    var errors: [String] {
        lock.withLock { lines.filter { $0.level == .error }.map(\.message) }
    }

    func write(_ level: LogLevel, category: String, message: String) {
        lock.withLock { lines.append((level, message)) }
    }
}
