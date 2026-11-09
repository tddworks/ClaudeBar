#if os(macOS) || os(Linux)
import Foundation
#if canImport(Glibc)
import Glibc
#endif

extension LogFile {
    /// Adds `line` to the end of the file at `url`, making the file if it
    /// isn't there: `O_APPEND`, so the OS puts each write at the end, and
    /// `O_CLOEXEC`, so a program this process starts doesn't keep the file.
    static func append(_ line: Data, to url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o666)
        }
        guard descriptor >= 0 else { throw failure("opening it") }
        defer { close(descriptor) }
        try line.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw failure("writing to it")
                }
                offset += written
            }
        }
    }

    /// Runs `body` while this process holds the lock on `<log>.lock`
    /// (`flock`, exclusive), waiting for another process that holds it.
    static func rotating(_ log: URL, _ body: () -> Void) throws {
        let descriptor = lockFile(for: log).withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o666)
        }
        guard descriptor >= 0 else { throw failure("opening its lock file") }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw failure("locking its lock file") }
        }
        defer { flock(descriptor, LOCK_UN) }
        body()
    }

    private static func failure(_ step: String) -> Error {
        let code = errno
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: "\(String(cString: strerror(code))) \(step)"])
    }
}
#endif
