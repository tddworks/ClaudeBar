import Foundation

/// The files a `files` glob names, changed since a date: `**` matches any
/// depth, `*` and `?` stay within one name. Hidden files are skipped, and the
/// result is in path order so the same logs always read the same way.
///
/// Each platform lists the folder its own way (`LogFileFinder+macOS`,
/// `+Linux`, `+Windows`): `listing(under:)` names every file under it and
/// `contentModified(_:)` says when one the glob names last changed.
enum LogFileFinder {
    static func files(matching pattern: String, changedSince since: Date) -> [URL] {
        let (root, rest) = split(pattern)
        guard !rest.isEmpty else {
            let url = URL(fileURLWithPath: root)
            return isRecent(url, since: since) ? [url] : []
        }
        guard let matcher = try? NSRegularExpression(pattern: "^" + regex(rest) + "$") else { return [] }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath()
        let files = listing(under: rootURL).filter { file in
            let relative = file.relativePath
            return matcher.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil
                && isRecent(file.url, since: since)
        }
        return files.map(\.url).sorted { $0.path < $1.path }
    }

    /// A file a folder's listing names: where it is, and its path from the
    /// folder with `/` between the names, which the glob is matched against.
    struct Listed {
        let url: URL
        let relativePath: String
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
        guard let modified = contentModified(url) else { return false }
        return modified >= since
    }
}
