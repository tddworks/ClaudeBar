import Foundation
import Testing
@testable import DataSources
#if os(Windows)
import WinSDK
#endif

/// The `TimeZoneSource` port's contract (MODULAR_DESIGN §10), run against
/// this platform's adapter: the zone it gives is the person's as their OS has
/// it, so at every instant it is as far from UTC as the OS's own clock says.
/// Two years of half hours cross every daylight-saving change the zone has.
/// Windows CI runs it again after setting a zone with daylight saving and one
/// without, so a UTC runner still tests both.
@Suite
struct TimeZoneContract {
    @Test func `should be as far from UTC as the OS says, every half hour from a year ago to a year ahead`() {
        let zone = Platform.current.timeZone.current()
        let start = (Date().timeIntervalSince1970 / 3600).rounded(.down) * 3600 - 365 * 86400
        let wrong = stride(from: start, to: start + 2 * 365 * 86400, by: 1800).compactMap { seconds -> String? in
            let instant = Date(timeIntervalSince1970: seconds)
            let os = OSClock.secondsFromGMT(at: instant)
            let given = zone.secondsFromGMT(for: instant)
            return os == given ? nil : "\(instant): the OS says \(os)s, \(zone.identifier) says \(given)s"
        }
        #expect(wrong.isEmpty, "\(wrong.count) instants differ, first: \(wrong.prefix(3))")
    }

    /// A day is named by writing a date out in the person's zone, so a zone
    /// this platform's Foundation can't format in is the adapter's to keep out.
    @Test func `should give a zone a date can be written in`() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = Platform.current.timeZone.current()
        let instant = Date(timeIntervalSince1970: 1_784_116_800)
        let text = formatter.string(from: instant)
        #expect(formatter.date(from: text) == instant, "\(formatter.timeZone.identifier) wrote \(text)")
    }
}

/// The OS's own offset from UTC at an instant, read without Foundation.
private enum OSClock {
    static func secondsFromGMT(at date: Date) -> Int {
        #if os(Windows)
        let ticks = UInt64((date.timeIntervalSince1970 + 11_644_473_600) * 10_000_000)
        var utcFile = FILETIME(dwLowDateTime: DWORD(truncatingIfNeeded: ticks), dwHighDateTime: DWORD(truncatingIfNeeded: ticks >> 32))
        var utc = SYSTEMTIME()
        var local = SYSTEMTIME()
        var localFile = FILETIME()
        guard FileTimeToSystemTime(&utcFile, &utc), SystemTimeToTzSpecificLocalTimeEx(nil, &utc, &local),
              SystemTimeToFileTime(&local, &localFile) else { return .min }
        let localTicks = UInt64(localFile.dwHighDateTime) << 32 | UInt64(localFile.dwLowDateTime)
        return Int((Int64(bitPattern: localTicks) - Int64(bitPattern: ticks)) / 10_000_000)
        #else
        var time = time_t(date.timeIntervalSince1970)
        var parts = tm()
        localtime_r(&time, &parts)
        return parts.tm_gmtoff
        #endif
    }
}
