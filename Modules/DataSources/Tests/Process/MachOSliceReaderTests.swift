import Foundation
import Testing

@testable import DataSources

/// Reads the architecture slices of the binaries ClaudeBar resolves and runs
/// (issue #251): an Intel-only CLI runs under Rosetta and macOS names
/// ClaudeBar in its "apps for Intel processors" warning.
@Suite
struct MachOSliceReaderTests {

    @Test
    func `should read a plain arm64 app as arm64`() throws {
        try Self.withFile(MachOFixtures.thin(.arm64)) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == [.arm64])
        }
    }

    @Test
    func `should read a plain Intel app as Intel-only`() throws {
        try Self.withFile(MachOFixtures.thin(.x86_64)) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == [.x86_64])
        }
    }

    @Test
    func `should read both slices of a universal app`() throws {
        try Self.withFile(MachOFixtures.universal([.arm64, .x86_64])) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == [.arm64, .x86_64])
        }
    }

    @Test
    func `should read a universal app whichever slice comes first`() throws {
        try Self.withFile(MachOFixtures.universal([.x86_64, .arm64])) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == [.x86_64, .arm64])
        }
    }

    @Test
    func `should read a universal app's newer 64-bit table too`() throws {
        try Self.withFile(MachOFixtures.universal([.arm64, .x86_64], magic64: true)) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == [.arm64, .x86_64])
        }
    }

    @Test
    func `should keep a universal app's unknown slices from looking like a native twin`() throws {
        // A fat binary whose slices are all architectures we don't know tells
        // us nothing useful; callers must keep today's behavior, so the reader
        // reports "can't tell" rather than "no native slice".
        var header = Data([0xCA, 0xFE, 0xBA, 0xBE])
        header.appendBEUInt32(1)
        header.appendBEUInt32(0x0000_0009)  // an old CPU type nobody ships anymore
        header.appendBEUInt32(0)
        header.appendBEUInt32(28)
        header.appendBEUInt32(0)
        header.appendBEUInt32(12)
        try Self.withFile(header) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == nil)
        }
    }

    @Test
    func `should admit it can't tell for a shell script`() throws {
        try Self.withFile(MachOFixtures.shellScript) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == nil)
        }
    }

    @Test
    func `should admit it can't tell for a file that isn't an app binary`() throws {
        try Self.withFile(MachOFixtures.plainText) { path in
            #expect(MachOSliceReader.architectures(atPath: path) == nil)
        }
    }

    @Test
    func `should admit it can't tell for a file that isn't there`() {
        #expect(MachOSliceReader.architectures(atPath: "/bin/claudebar-not-a-real-binary") == nil)
    }

    @Test
    func `should read macOS's own shell as a universal app`() {
        // The real thing: /bin/zsh has shipped arm64 + x86_64 since macOS 12.
        let slices = MachOSliceReader.architectures(atPath: "/bin/zsh")

        #expect(slices?.contains(.arm64) == true)
        #expect(slices?.contains(.x86_64) == true)
    }

    private static func withFile(_ data: Data, _ body: (String) -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-macho-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        body(url.path)
    }
}
