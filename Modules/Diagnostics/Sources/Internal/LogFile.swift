import Foundation

/// The file log on disk: a line is added to its end by the OS, the file made
/// if it isn't there. Several of the app's processes write one log (on Windows
/// the app and its hourly upload), each in its own order, so the OS, not a
/// process, decides where a line goes: no line takes another's place. No
/// program the process starts inherits the file. Each platform defines
/// `append(_:to:)` once: `LogFile+POSIX` on the Mac and Linux, `LogFile+Windows`.
enum LogFile {}
