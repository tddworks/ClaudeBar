import DataSources
import Foundation
import Mockable

/// *In use* — which login new terminal sessions of a CLI start with: one
/// file per CLI, `~/.claudebar/in-use/<command>`, holding the
/// login's folder. Empty, or no file, is the plain login the CLI already
/// uses. The shell lines `ShellSetup` writes read it on every `claude` or
/// `codex`, so the file is the only record: nothing else keeps a copy.
@Mockable
public protocol LoginsInUse: Sendable {
    /// The folder new sessions of `command` start with — `nil` for the plain login.
    func folder(for command: String) -> URL?
    /// Saves it; `nil` goes back to the plain login.
    func use(_ folder: URL?, for command: String) throws
}

/// The real files, under `~/.claudebar/in-use`.
public struct DiskLoginsInUse: LoginsInUse {
    public static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claudebar/in-use", isDirectory: true)

    public let root: URL

    public init(root: URL = DiskLoginsInUse.root) {
        self.root = root
    }

    public func folder(for command: String) -> URL? {
        guard let text = try? String(contentsOf: file(for: command), encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL
    }

    public func use(_ folder: URL?, for command: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Written whole and renamed into place, so a shell never reads half a path.
        try AtomicFile.write(Data((folder?.standardizedFileURL.path ?? "").utf8), to: file(for: command))
    }

    public func file(for command: String) -> URL {
        root.appendingPathComponent(command)
    }
}

