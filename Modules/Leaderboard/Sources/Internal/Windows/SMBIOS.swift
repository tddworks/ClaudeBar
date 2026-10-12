import Foundation

/// The SMBIOS table's system UUID (type 1, *System Information*, offset 8):
/// a PC's hardware UUID, kept by its firmware, as `wmic csproduct get uuid`
/// shows it. Pure bytes, so it builds and is tested everywhere, though only
/// `WindowsMachineIdentity` reads a table.
///
/// The table as `GetSystemFirmwareTable('RSMB')` answers it: an 8-byte header
/// (calling method, major, minor, DMI revision, length) and then the
/// structures, each a 4-byte header (type, formatted length, handle), its
/// formatted area, and its strings, each NUL-terminated, the set ended by one
/// more NUL ([DMTF DSP0134](https://www.dmtf.org/standards/smbios) §6.1).
enum SMBIOS {
    private static let headerLength = 8
    private static let systemInformation: UInt8 = 1
    private static let endOfTable: UInt8 = 127
    private static let uuidOffset = 8
    private static let uuidLength = 16

    /// Boards whose makers left the UUID unset: all zeros and all ones, which
    /// the standard reserves for "not present" and "not settable", and the
    /// sample value some boards ship with ([dmidecode](https://github.com/mirror/dmidecode/blob/master/dmidecode.c)
    /// prints it as any other). None of them names one machine.
    private static let placeholders: Set<String> = [
        "00000000-0000-0000-0000-000000000000",
        "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
        "03000200-0400-0500-0006-000700080009",
    ]

    /// The system UUID in `table`, formatted as the firmware's maker and
    /// Windows show it; `nil` when the table has no type 1 structure long
    /// enough to hold one (SMBIOS before 2.1), or holds a placeholder.
    static func systemUUID(in table: Data) -> String? {
        let bytes = [UInt8](table)
        var at = headerLength
        while at + 4 <= bytes.count {
            let type = bytes[at]
            let length = Int(bytes[at + 1])
            guard length >= 4, type != endOfTable else { return nil }
            if type == systemInformation, length >= uuidOffset + uuidLength, at + uuidOffset + uuidLength <= bytes.count {
                let uuid = format(Array(bytes[(at + uuidOffset)..<(at + uuidOffset + uuidLength)]))
                return placeholders.contains(uuid) ? nil : uuid
            }
            // Past the formatted area, then past the strings: they end at a double NUL.
            var end = at + length
            while end + 1 < bytes.count, !(bytes[end] == 0 && bytes[end + 1] == 0) { end += 1 }
            at = end + 2
        }
        return nil
    }

    /// Since SMBIOS 2.6 the first three fields are little-endian (DSP0134
    /// §7.2.1), which is how every firmware since writes it and how Windows
    /// reads it back.
    private static func format(_ b: [UInt8]) -> String {
        let hex = b.map { String(format: "%02X", $0) }
        return "\(hex[3])\(hex[2])\(hex[1])\(hex[0])-\(hex[5])\(hex[4])-\(hex[7])\(hex[6])-\(hex[8])\(hex[9])-\(hex[10...15].joined())"
    }
}
