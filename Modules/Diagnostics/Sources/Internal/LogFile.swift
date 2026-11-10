import Foundation

/// The file log on disk. Several of the app's processes write one log (the
/// app and its helpers, such as an hourly upload), each in its own order, so
/// the OS, not a process, decides where a line goes: a line is added to the
/// end of the file, which is made if it isn't there, and no line takes
/// another's place. No program the process starts inherits the file. Starting
/// a new file is done by one process at a time, holding a lock on
/// `<log>.lock` beside it. Each platform's folder defines `append(_:to:)` and
/// `rotating(_:_:)` once.
enum LogFile {
    /// The file beside `log` whose lock says a process is starting a new file.
    static func lockFile(for log: URL) -> URL {
        log.appendingPathExtension("lock")
    }
}
