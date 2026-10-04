import DataSources
import Foundation

/// Login folders kept in memory: what exists after adding, signing in and
/// removing, without touching the disk.
final class InMemoryLoginFolders: LoginFolders, @unchecked Sendable {
    private let lock = NSLock()
    private var folders: Set<String>

    init(_ existing: [URL] = []) {
        folders = Set(existing.map(\.standardizedFileURL.path))
    }

    /// Every folder that exists now.
    var all: Set<String> { lock.withLock { folders } }

    func exists(_ folder: URL) -> Bool {
        lock.withLock { folders.contains(folder.standardizedFileURL.path) }
    }

    func create(_ folder: URL) throws {
        try lock.withLock {
            guard folders.insert(folder.standardizedFileURL.path).inserted else { throw SignInError.folderExists }
        }
    }

    func delete(_ folder: URL) {
        _ = lock.withLock { folders.remove(folder.standardizedFileURL.path) }
    }
}
