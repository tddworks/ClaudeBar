import Foundation
import Mockable

/// The folders added logins live in — the one place adding and removing an
/// account touches the disk, so a test can watch it without one.
@Mockable
public protocol LoginFolders: Sendable {
    func exists(_ folder: URL) -> Bool
    /// Makes a NEW private folder (0700), and its parents. Throws when the
    /// folder is already there: a login is never written over another.
    func create(_ folder: URL) throws
    func delete(_ folder: URL)
}

/// The real disk.
public struct DiskLoginFolders: LoginFolders {
    public init() {}

    public func exists(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.path)
    }

    public func create(_ folder: URL) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: folder.path) else { throw SignInError.folderExists }
        try files.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    public func delete(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }
}
