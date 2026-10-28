import Quotas
import Diagnostics
import Foundation

/// Opens values an Electron app sealed with its safeStorage key, for a
/// `sealed` lookup (#655), keeping each app's key for the process's lifetime.
///
/// On the Mac every read of another app's Keychain item can put up macOS's
/// access dialog, and a refresh finds its key several times (readiness, the
/// fetch, the identity). So a key is read once and kept in memory, never
/// written; a kept key that no longer opens a value (the app made a new one)
/// is dropped and read again. A key that couldn't be read isn't asked for
/// again for `pause`, so a refused dialog isn't put up again by the same
/// refresh. One read at a time: providers refreshing together wait on the one
/// dialog.
final class SafeStorage: @unchecked Sendable {
    /// How long a key that couldn't be read is not asked for again.
    static let pause: TimeInterval = 60

    private let keys: any SafeStorageKeys
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var kept: [String: Data] = [:]
    private var unreadable: [String: (at: Date, place: String)] = [:]

    init(_ keys: any SafeStorageKeys, now: @escaping @Sendable () -> Date = { Date() }) {
        self.keys = keys
        self.now = now
    }

    /// `value` opened when it carries `sealed.prefix`; otherwise as it is.
    func open(_ value: String, _ sealed: SealedValues) throws -> String {
        guard value.hasPrefix(sealed.prefix) else { return value }
        guard let data = Data(base64Encoded: String(value.dropFirst(sealed.prefix.count))) else {
            throw Self.unopened(sealed.app)
        }
        lock.lock()
        defer { lock.unlock() }
        if let key = kept[sealed.app] {
            if let plain = text(keys.open(data, with: key)) { return plain }
            kept[sealed.app] = nil
        }
        if let last = unreadable[sealed.app], now().timeIntervalSince(last.at) < Self.pause {
            throw Self.unreadable(sealed.app, at: last.place)
        }
        let key: Data
        do {
            key = try keys.key(app: sealed.app)
        } catch let error as SafeStorageKeyUnreadable {
            AppLog.credentials.error("\(sealed.app)'s safeStorage key couldn't be read from \(error.place)")
            unreadable[sealed.app] = (now(), error.place)
            throw Self.unreadable(sealed.app, at: error.place)
        }
        unreadable[sealed.app] = nil
        guard let plain = text(keys.open(data, with: key)) else {
            AppLog.credentials.error("\(sealed.app)'s sealed value didn't open with its safeStorage key")
            throw Self.unopened(sealed.app)
        }
        kept[sealed.app] = key
        return plain
    }

    /// The opened bytes as text. The Mac's AES-CBC has no tag, so a wrong key
    /// can still pass its padding check; what it yields then is almost never UTF-8.
    private func text(_ data: Data?) -> String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func unreadable(_ app: String, at place: String) -> UsageError {
        .executionFailed("\(app) keeps its sign-in sealed, and its key (\(place)) couldn't be read. "
            + "Allow ClaudeBar to read it when asked, then refresh in a minute.")
    }

    private static func unopened(_ app: String) -> UsageError {
        .executionFailed("\(app)'s saved sign-in couldn't be opened with its key. Sign in to \(app) again, then refresh.")
    }
}
