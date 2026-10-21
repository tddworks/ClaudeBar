#if os(Linux)
import Foundation

/// Linux's zone: Foundation's, which reads `/etc/localtime` and `TZ`.
///
/// Named for Linux, as `WindowsTimeZone` is for Windows: SwiftPM names each
/// file's object after the file, so two platforms' files can't share one.
struct LinuxTimeZone: TimeZoneSource {
    func current() -> TimeZone { .current }
}
#endif