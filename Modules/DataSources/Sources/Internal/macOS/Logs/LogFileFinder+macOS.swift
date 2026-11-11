#if os(macOS)
import Foundation

extension LogFileFinder {
    /// Every visible file under `root`, at any depth, through Foundation's
    /// enumerator. A path is matched as it resolves, so a link that leads out
    /// of the folder is left out.
    static func listing(under root: URL) -> [Listed] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var files: [Listed] = []
        for case let url as URL in enumerator {
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else { continue }
            files.append(Listed(url: url, relativePath: String(path.dropFirst(prefix.count))))
        }
        return files
    }

    /// When a regular file's content last changed; `nil` for anything else.
    static func contentModified(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        return values.contentModificationDate
    }
}
#endif
