import Foundation

/// What an OS answers about its secret store, for a `keychain` lookup
/// (MODULAR_DESIGN §10, `Secrets`): an item found by its service and, when
/// several logins share one, its account. The Mac asks its Keychain, Windows
/// Credential Manager.
///
/// An adapter answers a password as its store keeps it and decodes nothing:
/// what a password holds (JSON, a raw token, the hex form the Mac's `security`
/// prints for a multi-line one) is `KeychainReader`'s to read. What "no
/// account" names is the adapter's alone, the same way for a read and a save,
/// so a refreshed login lands on the item it was read from.
public protocol KeychainItems: Sendable {
    /// The item's password as stored; `nil` when there is none or it can't be
    /// read.
    func password(service: String, account: String?) -> String?
    /// Writes `password` over the item `password(service:account:)` reads for
    /// the same name, or makes it. Answers whether it was kept.
    func save(_ password: String, service: String, account: String?) -> Bool
}

/// What an OS answers about the key an Electron app seals values with
/// (`safeStorage`), for a `sealed` lookup (#655): the Mac derives it from the
/// app's Keychain item, Windows unprotects it from the app's `Local State`.
/// What wraps a sealed value (Cursor's `cursor-safe-storage:v1:` and base64)
/// and how long a key is kept are neutral; an adapter knows only its OS's
/// scheme.
public protocol SafeStorageKeys: Sendable {
    /// The app's key, read from where this OS keeps it. Throws
    /// `SafeStorageKeyUnreadable` naming that place when it can't be read.
    func key(app: String) throws -> Data
    /// `sealed`'s plain bytes; `nil` when `key` doesn't open it.
    func open(_ sealed: Data, with key: Data) -> Data?
}

/// An app's safeStorage key couldn't be read from `place`, as a person names
/// it: `Keychain “Cursor Safe Storage”`.
public struct SafeStorageKeyUnreadable: Error, Sendable, Equatable {
    public let place: String

    public init(place: String) {
        self.place = place
    }
}
