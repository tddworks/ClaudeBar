#if os(Windows)
import Foundation
import WinSDK

extension LogFile {
    /// Adds `line` to the end of the file at `url`, making the file if it
    /// isn't there. The handle may only append (`FILE_APPEND_DATA` without
    /// `FILE_WRITE_DATA`), so Windows puts each write at the end. It has no
    /// security attributes, so no program this process starts inherits it.
    /// Not Foundation's atomic write, which a new log's first line went
    /// through: its new file was inherited by a program started meanwhile,
    /// the rename failed, and the line was lost (#692). While the handle is
    /// open, others may read the file, append to it, and rename it, as the
    /// other process does when the log passes its size.
    static func append(_ line: Data, to url: URL) throws {
        let opened = url.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(FILE_APPEND_DATA), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else { throw Failure("opening it") }
        defer { CloseHandle(handle) }
        try line.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                var written: DWORD = 0
                guard WriteFile(handle, bytes.baseAddress! + offset, DWORD(bytes.count - offset), &written, nil) else {
                    throw Failure("writing to it")
                }
                offset += Int(written)
            }
        }
    }

    /// Runs `body` while this process holds the lock on `<log>.lock`
    /// (`LockFileEx`, exclusive, on its first byte), waiting for another
    /// process that holds it. No program this process starts inherits it.
    static func rotating(_ log: URL, _ body: () -> Void) throws {
        let opened = lockFile(for: log).path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else { throw Failure("opening its lock file") }
        defer { CloseHandle(handle) }
        var overlapped = OVERLAPPED()
        guard LockFileEx(handle, DWORD(LOCKFILE_EXCLUSIVE_LOCK), 0, 1, 0, &overlapped) else {
            throw Failure("locking its lock file")
        }
        defer { UnlockFileEx(handle, 0, 1, 0, &overlapped) }
        body()
    }

    /// A line that didn't reach the file: the step and its Win32 error.
    private struct Failure: LocalizedError {
        let step: String
        let code: DWORD

        init(_ step: String, _ code: DWORD = GetLastError()) {
            self.step = step
            self.code = code
        }

        var errorDescription: String? { "Windows error \(code) \(step)" }
    }
}
#endif
