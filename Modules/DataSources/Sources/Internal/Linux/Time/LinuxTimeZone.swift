#if os(Linux)
import Foundation

/// Linux's zone: Foundation's, which reads `/etc/localtime` and `TZ`.
///
/// Foundation still knows names the OS's tzdata no longer carries (Ubuntu moved
/// the deprecated aliases, `Asia/Calcutta`, `Europe/Kiev`, …, to its
/// `tzdata-legacy` package): it answers such a `TZ` with a zone, but a
/// `DateFormatter` in that zone stops the process, and the OS's own clock,
/// with no file to read, keeps a fixed offset (UTC). So a zone with no file
/// under `/usr/share/zoneinfo` is the OS's offset, fixed: its fact, not a guess.
///
/// Named for Linux, as `WindowsTimeZone` is for Windows: SwiftPM names each
/// file's object after the file, so two platforms' files can't share one.
struct LinuxTimeZone: TimeZoneSource {
    func current() -> TimeZone {
        let zone = TimeZone.current
        if FileManager.default.fileExists(atPath: "/usr/share/zoneinfo/\(zone.identifier)") { return zone }
        return TimeZone(secondsFromGMT: Self.osSecondsFromGMT())!
    }

    /// The C library's offset from UTC now, as `date` shows it.
    private static func osSecondsFromGMT() -> Int {
        var now = time(nil)
        var parts = tm()
        localtime_r(&now, &parts)
        return parts.tm_gmtoff
    }
}
#endif
