import Foundation
import Testing
@testable import Leaderboard

/// A PC's hardware UUID from its SMBIOS table (design §2a): the type 1
/// structure's UUID, as Windows shows it, never a maker's placeholder.
@Suite
struct SMBIOSTests {
    private static let uuidBytes: [UInt8] = [
        0x44, 0x33, 0x22, 0x11, 0x66, 0x55, 0x88, 0x77, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x01,
    ]

    /// A table as the firmware answers: the raw header, a BIOS structure
    /// with two strings, the system structure, and the end.
    private static func table(uuid: [UInt8] = uuidBytes, systemLength: UInt8 = 0x1B) -> Data {
        var bytes: [UInt8] = [0, 3, 4, 0, 0, 0, 0, 0] // calling method, 3.4, DMI revision, length (unused here)
        bytes += [0, 0x18, 0x00, 0x00] + [UInt8](repeating: 0, count: 0x14) // type 0, 24 bytes formatted
        bytes += Array("American Megatrends\0F7\0\0".utf8)
        bytes += [1, systemLength, 0x01, 0x00, 1, 2, 3, 4] // type 1, handle 1, four string indexes
        bytes += uuid + [1, 5, 6] // wake-up type, SKU, family
        bytes += Array("Gigabyte\0Z790 UD AC\0x.x\0Default string\0SKU\0Family\0\0".utf8)
        bytes += [127, 4, 0xFF, 0xFF, 0, 0] // end of table
        return Data(bytes)
    }

    @Test func `should read the system UUID with its first three fields little-endian, as Windows shows it`() {
        #expect(SMBIOS.systemUUID(in: Self.table()) == "11223344-5566-7788-99AA-BBCCDDEEFF01")
    }

    @Test(arguments: [
        [UInt8](repeating: 0x00, count: 16),
        [UInt8](repeating: 0xFF, count: 16),
        [0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x05, 0x00, 0x06, 0x00, 0x07, 0x00, 0x08, 0x00, 0x09],
    ])
    func `should read no UUID from a board whose maker left a placeholder`(uuid: [UInt8]) {
        #expect(SMBIOS.systemUUID(in: Self.table(uuid: uuid)) == nil)
    }

    @Test func `should read no UUID from a system structure too short to hold one, or a table without one`() {
        #expect(SMBIOS.systemUUID(in: Self.table(systemLength: 0x08)) == nil)
        #expect(SMBIOS.systemUUID(in: Data([0, 2, 0, 0, 0, 0, 0, 0, 127, 4, 0, 0, 0, 0])) == nil)
        #expect(SMBIOS.systemUUID(in: Data()) == nil)
        #expect(SMBIOS.systemUUID(in: Data([0, 2, 0, 0, 0, 0, 0, 0, 1, 0x1B, 0, 0, 1, 2])) == nil, "cut off mid-structure")
    }
}
