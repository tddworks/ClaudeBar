import Foundation
import Domain

/// Bridges a legacy UserDefaults credential to its secure credential-store replacement.
///
/// Reads prefer secure storage. When only a legacy value exists, it is copied to
/// secure storage and removed from UserDefaults only after persistence succeeds.
struct SecureCredentialMigration {
    let secureStore: any CredentialRepository
    let legacyStore: UserDefaults
    let secureKey: String
    let legacyKey: String

    /// Saves a credential securely and removes its legacy copy after verification.
    func save(_ value: String) {
        secureStore.save(value, forKey: secureKey)
        if secureStore.get(forKey: secureKey) == value {
            legacyStore.removeObject(forKey: legacyKey)
        }
    }

    /// Reads the secure value or migrates and returns the legacy value.
    func get() -> String? {
        if let value = secureStore.get(forKey: secureKey) {
            return value
        }

        guard let legacyValue = legacyStore.string(forKey: legacyKey) else {
            return nil
        }

        save(legacyValue)
        return legacyValue
    }

    /// Deletes both credential copies after secure deletion succeeds.
    /// - Returns: `true` when both copies are absent after the operation.
    @discardableResult
    func delete() -> Bool {
        guard secureStore.delete(forKey: secureKey) else {
            return false
        }

        legacyStore.removeObject(forKey: legacyKey)
        return legacyStore.object(forKey: legacyKey) == nil
    }

    /// Returns whether a secure or legacy credential is available.
    func exists() -> Bool {
        get() != nil
    }
}
