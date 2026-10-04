import Foundation
import Domain

/// The leaderboard key's private half, kept like Notify!'s token: the
/// Keychain first, read back to prove it landed, and the app's UserDefaults
/// credential store when the Keychain refuses a locally built, ad-hoc signed
/// app. Never `settings.json`, never logged.
public struct CredentialSigningKeyStore: SigningKeyStore {
    private let secure: any CredentialRepository
    private let fallback: any CredentialRepository

    public init(secure: any CredentialRepository = KeychainCredentialRepository.shared,
                fallback: any CredentialRepository = UserDefaultsCredentialRepository(defaults: .standard)) {
        self.secure = secure
        self.fallback = fallback
    }

    public func load() -> Data? {
        (secure.get(forKey: Self.key) ?? fallback.get(forKey: Self.key)).flatMap { Data(base64Encoded: $0) }
    }

    public func save(_ rawKey: Data) {
        let encoded = rawKey.base64EncodedString()
        secure.save(encoded, forKey: Self.key)
        if secure.get(forKey: Self.key) == encoded {
            fallback.delete(forKey: Self.key)
            return
        }
        AppLog.credentials.warning("Leaderboard key could not be stored in the Keychain, keeping it in the app credential store instead")
        fallback.save(encoded, forKey: Self.key)
    }

    public func delete() {
        secure.delete(forKey: Self.key)
        fallback.delete(forKey: Self.key)
    }

    /// Whether the key is in the Keychain rather than the fallback store.
    public var isSecure: Bool { secure.get(forKey: Self.key) != nil }

    private static let key = CredentialKey.leaderboardSigningKey
}
