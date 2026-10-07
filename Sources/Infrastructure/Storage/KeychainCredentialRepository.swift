import Domain
import Foundation

/// Secrets in the login Keychain — Domain's `CredentialRepository` over Kotlin's
/// `KeychainCredentials`, which owns the Keychain calls (storage, MODULAR_DESIGN §8).
public final class KeychainCredentialRepository: CredentialRepository, @unchecked Sendable {
    /// Shared production credential store for ClaudeBar.
    public static let shared = KeychainCredentialRepository()

    private let keychain: KeychainCredentials

    /// - Parameter service: The Keychain service that namespaces the items.
    public init(service: String = "com.tddworks.claudebar.credentials") {
        keychain = KeychainCredentials(service: service)
    }

    public func save(_ value: String, forKey key: String) { keychain.save(value: value, key: key) }

    public func get(forKey key: String) -> String? { keychain.get(key: key) }

    @discardableResult
    public func delete(forKey key: String) -> Bool { keychain.delete(key: key) }

    public func exists(forKey key: String) -> Bool { keychain.exists(key: key) }
}

extension KeychainCredentials: @retroactive @unchecked Sendable {}
