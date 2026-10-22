import Foundation
import Domain

/// A destination's secrets — Notify!'s device token, a webhook's URL — in the
/// Keychain, with the app credential store as the fallback. The one copy of
/// that rule, so every destination falls back alike and every pane can say so.
public final class KeychainDestinationSecrets: DestinationSecrets, @unchecked Sendable {
    private let keychain: any CredentialRepository
    private let fallback: any CredentialRepository

    /// `fallback` is the same UserDefaults credential store that holds the
    /// GitHub, MiniMax and DeepSeek tokens: the app's existing bar, not a new
    /// low, and never the first choice.
    public init(
        keychain: any CredentialRepository = KeychainCredentialRepository.shared,
        fallback: any CredentialRepository = UserDefaultsCredentialRepository.shared
    ) {
        self.keychain = keychain
        self.fallback = fallback
    }

    public func save(_ value: String, forKey key: String) {
        keychain.save(value, forKey: key)

        // Prove it landed, rather than assume. `CredentialRepository.save` has no
        // way to report a refusal, and the Keychain does refuse: a locally built
        // ClaudeBar is ad-hoc signed (`CODE_SIGN_IDENTITY` is "-"), so it has no
        // stable identity for a Keychain item's access control to name, and both
        // the read and the write come back errSecAuthFailed (-25293). A release
        // build signed with a Developer ID is unaffected.
        if keychain.get(forKey: key) == value {
            // Clear an earlier fallback copy, so a build that regains the
            // Keychain stops leaving a plaintext one behind.
            fallback.delete(forKey: key)
            return
        }
        AppLog.credentials.warning(
            "\(key) could not be stored in the Keychain, keeping it in the app credential store instead"
        )
        fallback.save(value, forKey: key)
    }

    public func get(forKey key: String) -> String? {
        keychain.get(forKey: key) ?? fallback.get(forKey: key)
    }

    @discardableResult
    public func delete(forKey key: String) -> Bool {
        // Both stores, always: a copy left in the one this build doesn't read
        // would come back the day the other one starts working.
        let fromKeychain = keychain.delete(forKey: key)
        let fromFallback = fallback.delete(forKey: key)
        return fromKeychain && fromFallback
    }

    public func isInKeychain(_ key: String) -> Bool {
        keychain.get(forKey: key) != nil
    }
}
