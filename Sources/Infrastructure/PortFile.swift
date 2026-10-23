import Foundation

/// A file holding the port a local server is listening on — the one place a
/// script reads the real number from. Written on start (the real number,
/// default or not), removed on stop, so a file that exists never lies. The
/// hook server and the local API each keep one.
public struct PortFile: Sendable {
    /// Where the number is kept.
    public let path: String

    public init(path: String) {
        self.path = path
    }

    /// `~/.claude/claudebar-hook-port` — read by the hook scripts.
    public static var hooks: PortFile { inHome(".claude/claudebar-hook-port") }

    /// `~/.claudebar/api-port` — read by a launcher and the Local API pane.
    public static var localAPI: PortFile { inHome(".claudebar/api-port") }

    private static func inHome(_ relative: String) -> PortFile {
        PortFile(path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative).path)
    }

    /// Writes the port number, creating its folder if needed.
    public func write(_ port: Int) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "\(port)".write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The port the file holds, or `nil` — no file, or nothing readable in it.
    public func read() -> Int? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes the file.
    public func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
