#if os(Windows)
import Foundation
import Testing
@testable import DataSources

/// Foundation on Windows has zones it can't format a date in, and a formatter
/// in one stops the whole process (0xC000001D). `WindowsZones.unformattable`
/// keeps them out; this proves it on the platform whose fact it is. Every OS's
/// own zone is held to the same by `TimeZoneContract`.
@Suite
struct WindowsZoneFormatTests {
    /// 2026-07-15 12:00 UTC: summer in the northern hemisphere.
    private static let july = Date(timeIntervalSince1970: 1_784_116_800)

    /// A zone a newer table brings in fails this run, not a person's app.
    @Test func `should give, for every Windows zone, a zone a date can be written out and read back in`() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let wrong = WindowsZones.iana.keys.sorted().compactMap { key -> String? in
            formatter.timeZone = WindowsZones.zone(key: key, daylightSavingOff: false, secondsFromGMT: 0)
            let text = formatter.string(from: Self.july)
            return formatter.date(from: text) == Self.july ? nil : "\(key): \(text)"
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }
}
#endif
