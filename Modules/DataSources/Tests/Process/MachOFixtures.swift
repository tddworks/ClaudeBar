import Foundation

@testable import DataSources

/// Builds minimal Mach-O headers for the architecture tests. Only the header
/// bytes the slice reader looks at are filled in; the rest is zeros.
enum MachOFixtures {

    static let arm64CPUType: UInt32 = 0x0100_000C
    static let x86_64CPUType: UInt32 = 0x0100_0007

    /// A thin (single-architecture) 64-bit Mach-O image header.
    static func thin(_ arch: BinaryArchitecture) -> Data {
        var d = Data([0xCF, 0xFA, 0xED, 0xFE])
        d.appendLEUInt32(arch == .arm64 ? arm64CPUType : x86_64CPUType)
        d.appendLEUInt32(0)  // cpusubtype
        d.appendLEUInt32(2)  // filetype: MH_EXECUTE
        d.appendLEUInt32(0)  // ncmds
        d.appendLEUInt32(0)  // sizeofcmds
        d.appendLEUInt32(0)  // flags
        d.appendLEUInt32(0)  // reserved
        return d
    }

    /// A universal binary fat header listing the given architectures.
    static func universal(_ archs: [BinaryArchitecture], magic64: Bool = false) -> Data {
        var d = Data(magic64 ? [0xCA, 0xFE, 0xBA, 0xBF] : [0xCA, 0xFE, 0xBA, 0xBE])
        d.appendBEUInt32(UInt32(archs.count))

        // fat_arch carries 32-bit offsets and sizes; fat_arch_64 widens those
        // to 64 bits, which is what makes its entries 32 bytes.
        let entrySize = magic64 ? 32 : 20
        for (index, arch) in archs.enumerated() {
            let offset = UInt64(8 + archs.count * entrySize + index * 16)
            d.appendBEUInt32(arch == .arm64 ? arm64CPUType : x86_64CPUType)
            d.appendBEUInt32(0)  // cpusubtype
            if magic64 {
                d.appendBEUInt64(offset)
                d.appendBEUInt64(16)  // size
                d.appendBEUInt32(12)  // align (2^12)
                d.appendBEUInt32(0)  // reserved
            } else {
                d.appendBEUInt32(UInt32(offset))
                d.appendBEUInt32(16)  // size
                d.appendBEUInt32(12)  // align (2^12)
            }
        }
        return d
    }

    /// A shell script: a real file a user's CLI could be, but no Mach-O header.
    static var shellScript: Data {
        Data("#!/bin/sh\necho hi\n".utf8)
    }

    /// Plain text that is neither Mach-O nor a script.
    static var plainText: Data {
        Data("not a binary\n".utf8)
    }

    /// Writes `data` to a fresh executable file under a new temporary folder
    /// and returns its full path. `name` is the CLI tool's file name.
    static func writeExecutable(
        _ data: Data,
        name: String,
        in root: URL,
        subpath: String
    ) throws -> String {
        let dir = root.appendingPathComponent(subpath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }
}

extension Data {
    mutating func appendLEUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendBEUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBEUInt64(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
