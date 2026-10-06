import Darwin
import Foundation

/// The processor architecture a Mach-O binary slice is built for.
enum BinaryArchitecture: Equatable, Sendable {
    case arm64
    case x86_64

    /// The architecture this Mac runs natively — `arm64` on Apple Silicon even
    /// while ClaudeBar itself runs translated, since the question is what the
    /// children it spawns will run as.
    static var current: BinaryArchitecture {
        guard let machine = Self.machine else { return .arm64 }
        return machine.hasPrefix("x86_64") ? .x86_64 : .arm64
    }

    /// `hw.machine`: the kernel's architecture, not this process's.
    private static var machine: String? {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}

/// Reads the architecture slices recorded in a Mach-O binary — thin or
/// universal — straight from its header bytes, so ClaudeBar can tell whether
/// the CLIs it resolves will run natively or under Rosetta (issue #251).
///
/// Nothing is spawned and only the first few hundred bytes are read: the
/// Mach-O 64 header, or the fat table of a universal binary.
enum MachOSliceReader {

    /// The architectures the binary at `path` contains, in file order.
    ///
    /// Returns nil when the file is missing or is not a Mach-O image whose
    /// slices we understand — a shell script (the usual npm-wrapper shape), a
    /// plain data file, or a binary built only for architectures we don't know.
    /// Callers keep today's behavior on nil: no arch info is no reason to
    /// change a decision.
    static func architectures(atPath path: String) -> [BinaryArchitecture]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: maxHeaderBytes)
        return architectures(fromHeader: header)
    }

    /// The parse itself, over whatever the first `read` of the file returned.
    static func architectures(fromHeader header: Data) -> [BinaryArchitecture]? {
        guard header.count >= 8 else { return nil }
        let bytes = [UInt8](header)

        switch Array(bytes[0..<4]) {
        case [0xCF, 0xFA, 0xED, 0xFE]:  // MH_MAGIC_64, little-endian on disk
            return [architecture(cputype: bytes.littleEndianUInt32(at: 4))].compactMap { $0 }
        case [0xFE, 0xED, 0xFA, 0xCF]:  // MH_CIGAM_64, byte-swapped
            return [architecture(cputype: bytes.bigEndianUInt32(at: 4))].compactMap { $0 }
        case [0xCA, 0xFE, 0xBA, 0xBE]:  // FAT_MAGIC
            return fatArchitectures(bytes, entrySize: 20)
        case [0xCA, 0xFE, 0xBA, 0xBF]:  // FAT_MAGIC_64
            return fatArchitectures(bytes, entrySize: 32)
        default:
            return nil
        }
    }

    /// Walks a fat table's `fat_arch` / `fat_arch_64` entries, whose `cputype`
    /// fields are big-endian regardless of the host.
    private static func fatArchitectures(_ bytes: [UInt8], entrySize: Int) -> [BinaryArchitecture]? {
        let count = Int(bytes.bigEndianUInt32(at: 4))
        guard count > 0, count <= maxFatEntries else { return nil }

        var slices: [BinaryArchitecture] = []
        for index in 0..<count {
            let at = 8 + index * entrySize
            guard at + 4 <= bytes.count else { break }
            if let arch = architecture(cputype: bytes.bigEndianUInt32(at: at)) {
                slices.append(arch)
            }
        }
        return slices.isEmpty ? nil : slices
    }

    private static func architecture(cputype: UInt32) -> BinaryArchitecture? {
        switch cputype {
        case 0x0100_000C: .arm64  // CPU_TYPE_ARM64
        case 0x0100_0007: .x86_64  // CPU_TYPE_X86_64
        default: nil
        }
    }

    /// Room for the fixed header plus a fat table of `maxFatEntries` entries
    /// (`fat_arch_64` is the wider one at 32 bytes). Real universal binaries
    /// carry at most a handful of slices.
    private static let maxHeaderBytes = 8 + 16 * 32
    private static let maxFatEntries = 16
}

private extension [UInt8] {
    func bigEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
