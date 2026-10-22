import Foundation
import Mockable

/// A destination's secrets — Notify!'s device token, a webhook's URL — kept in
/// the Keychain, or, on a build the Keychain refuses, in the app credential
/// store. The one owner of that fallback, so every destination falls back the
/// same way and every pane can say so. Not the provider vault (`SecretVault`),
/// which keeps provider keys and has no fallback.
@Mockable
public protocol DestinationSecrets: Sendable {
    /// Keeps `value` in the Keychain if a read-back proves it landed, else in the fallback.
    func save(_ value: String, forKey key: String)
    /// The Keychain's copy first, then the fallback's.
    func get(forKey key: String) -> String?
    /// Removes it from both. `true` when it is gone from both.
    @discardableResult
    func delete(forKey key: String) -> Bool
    /// Whether the Keychain holds it, rather than the fallback.
    func isInKeychain(_ key: String) -> Bool
}
