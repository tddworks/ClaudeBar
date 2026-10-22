#if os(Linux)
import Foundation

/// Whether a line holds a fragment, byte for byte: the JSON lines reader's
/// prefilter, so most lines are never parsed. `memmem` is glibc's.
enum ByteSearch {
    static func contains(_ fragment: [UInt8], in line: UnsafeRawBufferPointer) -> Bool {
        guard let base = line.baseAddress else { return fragment.isEmpty }
        return memmem(base, line.count, fragment, fragment.count) != nil
    }
}
#endif
