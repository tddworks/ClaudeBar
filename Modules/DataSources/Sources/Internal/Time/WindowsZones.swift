import Foundation

/// A Windows person's zone, from what the OS says about it (#565). Windows
/// names a zone by a registry key (`Korea Standard Time`) that Foundation
/// doesn't take; CLDR's `windowsZones` (`iana`, generated from `Vendor/CLDR`)
/// joins the key to an IANA zone, the one ICU uses. Neutral, so it is tested
/// on every platform; only reading the key is Windows'.
enum WindowsZones {
    /// The key's IANA zone, with every daylight-saving change it has. The OS's
    /// own offset, fixed, when the person turned daylight saving's automatic
    /// adjustment off (the OS then keeps standard time all year), when the
    /// table doesn't know the key, or when the zone is one Foundation on
    /// Windows can't format in: still the OS's fact for now, never a guess.
    static func zone(key: String, daylightSavingOff: Bool, secondsFromGMT: Int) -> TimeZone {
        if !daylightSavingOff, let name = iana[key], !unformattable.contains(name),
           let zone = TimeZone(identifier: name) {
            return zone
        }
        // Windows' offsets lie within ±14 hours; Foundation takes up to ±18.
        return TimeZone(secondsFromGMT: secondsFromGMT)!
    }

    /// Zones Foundation on Windows (Swift 6.3.3) has but can't format in: a
    /// `DateFormatter` in one stops the process (0xC000001D), found by trying
    /// every zone in the table on a Windows PC. Each has kept one offset since
    /// 2022 or earlier, so the OS's offset is the same answer.
    static let unformattable: Set<String> = [
        "America/Mazatlan", "America/Whitehorse", "Asia/Qyzylorda", "Etc/UTC", "Europe/Volgograd",
    ]
}
