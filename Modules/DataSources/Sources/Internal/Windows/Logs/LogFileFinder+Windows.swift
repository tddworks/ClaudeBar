#if os(Windows)
import Foundation
import WinSDK

extension LogFileFinder {
    /// Every visible file under `root`, at any depth, read from the folders'
    /// own entries (`FindFirstFileExW`). Foundation's enumerator opens every
    /// file it lists to read it, twice with `LogFileFinder`'s path check, and
    /// each such open waits for the antivirus when Windows hasn't seen the
    /// file for a while: a folder of 15,000 session files took minutes. Here
    /// no file is opened. As Foundation's does, the listing doesn't enter a
    /// linked folder, and a link to a file is left out.
    static func listing(under root: URL) -> [Listed] {
        var files: [Listed] = []
        var folders: [(url: URL, relativePath: String)] = [(root, "")]
        while let folder = folders.popLast() {
            forEachEntry(in: folder.url) { name, attributes, reparseTag in
                guard attributes & DWORD(FILE_ATTRIBUTE_HIDDEN) == 0 else { return }
                let isLink = attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) != 0
                let relativePath = folder.relativePath.isEmpty ? name : folder.relativePath + "/" + name
                if attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0 {
                    if !isLink { folders.append((folder.url.appendingPathComponent(name, isDirectory: true), relativePath)) }
                } else if !(isLink && reparseTag == IO_REPARSE_TAG_SYMLINK) {
                    files.append(Listed(url: folder.url.appendingPathComponent(name, isDirectory: false),
                                        relativePath: relativePath))
                }
            }
        }
        return files
    }

    /// When a regular file's content last changed; `nil` for anything else.
    /// Asked of the file's own record, not the folder's entry: NTFS leaves
    /// the entry at its old time while a writer holds the file open, and a
    /// session still being written would look unchanged for days.
    static func contentModified(_ url: URL) -> Date? {
        var data = WIN32_FILE_ATTRIBUTE_DATA()
        guard url.path.withCString(encodedAs: UTF16.self, { GetFileAttributesExW($0, GetFileExInfoStandard, &data) }),
              data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == 0,
              data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0 || !isSymbolicLink(url)
        else { return nil }
        let ticks = Int64(data.ftLastWriteTime.dwHighDateTime) << 32 | Int64(data.ftLastWriteTime.dwLowDateTime)
        // Windows counts 100-nanosecond ticks from 1601.
        return Date(timeIntervalSince1970: Double(ticks - 116_444_736_000_000_000) / 10_000_000)
    }

    /// Each entry of `folder` but `.` and `..`: its name, attributes, and the
    /// kind of link it is when it is one.
    private static func forEachEntry(in folder: URL, _ body: (String, DWORD, DWORD) -> Void) {
        var data = WIN32_FIND_DATAW()
        let handle = (folder.path + "/*").withCString(encodedAs: UTF16.self) {
            FindFirstFileExW($0, FindExInfoBasic, &data, FindExSearchNameMatch, nil, DWORD(FIND_FIRST_EX_LARGE_FETCH))
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return }
        defer { FindClose(handle) }
        repeat {
            let name = withUnsafeBytes(of: data.cFileName) {
                String(decodingCString: $0.bindMemory(to: WCHAR.self).baseAddress!, as: UTF16.self)
            }
            if name != ".", name != ".." { body(name, data.dwFileAttributes, data.dwReserved0) }
        } while FindNextFileW(handle, &data)
    }

    /// Whether the entry at `url` is a symbolic link, which Foundation never
    /// counted as a regular file.
    private static func isSymbolicLink(_ url: URL) -> Bool {
        var data = WIN32_FIND_DATAW()
        let handle = url.path.withCString(encodedAs: UTF16.self) {
            FindFirstFileExW($0, FindExInfoBasic, &data, FindExSearchNameMatch, nil, 0)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return false }
        FindClose(handle)
        return data.dwFileAttributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) != 0 && data.dwReserved0 == IO_REPARSE_TAG_SYMLINK
    }
}
#endif
