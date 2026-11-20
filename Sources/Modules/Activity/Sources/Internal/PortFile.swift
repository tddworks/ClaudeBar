import Foundation

/// A file holding the port a local server is listening on — the one place a
/// script reads the real number from. Written on start (the real number,
/// default or not), removed on stop, so a file that exists never lies. The
/// hook server keeps this one; the local API keeps its own.
struct PortFile: Sendable {
    /// Where the number is kept.
    let path: String

    init(path: String) {
        self.path = path
    }

    /// `~/.claude/claudebar-hook-port` — read by the hook scripts.
    static var hooks: PortFile { inHome(".claude/claudebar-hook-port") }

    private static func inHome(_ relative: String) -> PortFile {
        PortFile(path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative).path)
    }

    /// Writes the port number, creating its folder if needed.
    func write(_ port: Int) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "\(port)".write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The port the file holds, or `nil` — no file, or nothing readable in it.
    func read() -> Int? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes the file.
    func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
