/// Where a log line goes (MODULAR_DESIGN §6): OSLog on the Mac
/// (`Internal/macOS`), and the file log on every platform. `AppLog` picks the
/// platform's sinks.
protocol LogSink: Sendable {
    func write(_ level: LogLevel, category: String, message: String)
    /// Returns once every line written so far has reached where it goes.
    func flush()
}

/// A line's level, as OSLog names it.
enum LogLevel: Sendable {
    case debug, info, notice, warning, error
}
