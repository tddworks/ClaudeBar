#if os(Linux)
import Foundation

extension AtomicFile {
    /// Puts `data` in place of the file at `url`: Foundation's atomic write,
    /// as on the Mac.
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
#endif
