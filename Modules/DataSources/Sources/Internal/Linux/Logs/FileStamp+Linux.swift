#if os(Linux)
import Foundation

extension FileStamp {
    /// The file's inode, size, and modification and change times to the
    /// nanosecond. Linux spells the last two `st_mtim` and `st_ctim`; the
    /// Mac's `st_mtimespec` and `st_ctimespec` are the same fields.
    init?(url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        inode = UInt64(info.st_ino)
        size = UInt64(info.st_size)
        modifiedNanos = Int64(info.st_mtim.tv_sec) * 1_000_000_000 + Int64(info.st_mtim.tv_nsec)
        changedNanos = Int64(info.st_ctim.tv_sec) * 1_000_000_000 + Int64(info.st_ctim.tv_nsec)
    }
}
#endif
