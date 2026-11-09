#if os(Windows)
import Foundation
import WinSDK

extension AtomicFile {
    /// Puts `data` in place of the file at `url`: it's written whole to a new
    /// file beside it, which is then renamed over it.
    ///
    /// Not `Data.write(to:options: .atomic)`: on Windows, Foundation (6.3.3)
    /// opens its new file with a C runtime descriptor that child processes
    /// inherit, and lets no one else delete it. A program this process started
    /// while that was open (the Windows client's `schtasks.exe`, anything
    /// started with `Foundation.Process`) kept a copy for as long as it ran,
    /// the rename failed with a sharing violation (Win32 error 32), and the
    /// save was lost, its new file left behind (#692). Here one handle, which no
    /// child inherits, writes the new file and renames it; until it closes,
    /// others may only read the file. A program holding `url` itself open for
    /// a moment without letting it be replaced (error 32 or 5) is waited for,
    /// up to a second.
    public static func write(_ data: Data, to url: URL) throws {
        let fresh = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        // No security attributes: the handle isn't inherited.
        let opened = fresh.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_WRITE) | DWORD(DELETE), DWORD(FILE_SHARE_READ), nil, DWORD(CREATE_NEW),
                        DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle = opened, handle != INVALID_HANDLE_VALUE else { throw SaveFailure("making a new file beside it") }
        var renamed = false
        defer {
            CloseHandle(handle)
            if !renamed { _ = fresh.path.withCString(encodedAs: UTF16.self) { DeleteFileW($0) } }
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                var written: DWORD = 0
                guard WriteFile(handle, bytes.baseAddress! + offset, DWORD(bytes.count - offset), &written, nil) else {
                    throw SaveFailure("writing the new file")
                }
                offset += Int(written)
            }
        }
        guard FlushFileBuffers(handle) else { throw SaveFailure("writing the new file") }
        var waited = 0
        while !rename(handle, to: url) {
            let error = GetLastError()
            guard error == DWORD(ERROR_SHARING_VIOLATION) || error == DWORD(ERROR_ACCESS_DENIED), waited < 1000 else {
                throw SaveFailure("putting the new file in its place", error)
            }
            Sleep(50)
            waited += 50
        }
        renamed = true
    }

    /// Renames the open file to `url`, replacing what's there even while
    /// others have it open, as long as they let it be deleted (POSIX semantics).
    private static func rename(_ handle: HANDLE, to url: URL) -> Bool {
        let target = Array(url.path.utf16)
        let nameOffset = MemoryLayout<FILE_RENAME_INFO>.offset(of: \FILE_RENAME_INFO.FileName)!
        // As Foundation sizes it: the structure, then the name and its terminator.
        let size = MemoryLayout<FILE_RENAME_INFO>.size + (target.count + 1) * MemoryLayout<WCHAR>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<FILE_RENAME_INFO>.alignment)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let info = buffer.bindMemory(to: FILE_RENAME_INFO.self, capacity: 1)
        info.pointee.Flags = DWORD(FILE_RENAME_FLAG_POSIX_SEMANTICS | FILE_RENAME_FLAG_REPLACE_IF_EXISTS)
        info.pointee.FileNameLength = DWORD(target.count * MemoryLayout<WCHAR>.size)
        target.withUnsafeBytes { (buffer + nameOffset).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        return SetFileInformationByHandle(handle, FileRenameInfoEx, buffer, DWORD(size))
    }

    /// A save that didn't reach the file: the step and its Win32 error.
    private struct SaveFailure: LocalizedError {
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
