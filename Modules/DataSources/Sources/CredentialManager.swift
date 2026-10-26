#if os(Windows)
import Foundation

/// Windows' Credential Manager, asked one call at a time across the process.
/// Changed by several threads at once, it answers each change as made and
/// keeps only some: deleted items come back and overwrites revert (#641). So
/// every module that calls it, the `keychain` lookup's store and the
/// leaderboard's key store alike, makes each call inside `oneAtATime`.
public enum CredentialManager {
    private static let lock = NSLock()

    /// Runs `call` while no other Credential Manager call of this process runs.
    public static func oneAtATime<T>(_ call: () throws -> T) rethrows -> T {
        try lock.withLock(call)
    }
}
#endif
