import Foundation

/// The files a `files` glob names, changed since a date: `**` matches any
/// depth, `*` and `?` stay within one name. Hidden files are skipped, and the
/// result is in path order so the same logs always read the same way.
enum LogFileFinder {
    static func files(matching pattern: String, changedSince since: Date) -> [URL] {
        let (root, rest) = split(pattern)
        guard !rest.isEmpty else {
            let url = URL(fileURLWithPath: root)
            return isRecent(url, since: since) ? [url] : []
        }
        guard let matcher = try? NSRegularExpression(pattern: "^" + regex(rest) + "$") else { return [] }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var files: [URL] = []
        for case let url as URL in enumerator {
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            guard matcher.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil,
                  isRecent(url, since: since) else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// The folder before the first wildcard, and the pattern after it.
    static func split(_ pattern: String) -> (root: String, rest: String) {
        let components = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let firstWild = components.firstIndex(where: { $0.contains { "*?[".contains($0) } }) else {
            return (pattern, "")
        }
        let root = components[..<firstWild].joined(separator: "/")
        return (root.isEmpty ? "/" : root, components[firstWild...].joined(separator: "/"))
    }

    static func regex(_ glob: String) -> String {
        var result = ""
        var index = glob.startIndex
        while index < glob.endIndex {
            let character = glob[index]
            let next = glob.index(after: index)
            if character == "*", next < glob.endIndex, glob[next] == "*" {
                let afterStars = glob.index(after: next)
                if afterStars < glob.endIndex, glob[afterStars] == "/" {
                    result += "(?:[^/]+/)*"
                    index = glob.index(after: afterStars)
                } else {
                    result += ".*"
                    index = afterStars
                }
                continue
            }
            switch character {
            case "*": result += "[^/]*"
            case "?": result += "[^/]"
            default: result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = next
        }
        return result
    }

    private static func isRecent(_ url: URL, since: Date) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true, let modified = values.contentModificationDate else { return false }
        return modified >= since
    }
}
