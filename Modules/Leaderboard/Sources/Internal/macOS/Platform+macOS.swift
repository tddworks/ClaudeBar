#if os(macOS)
import Foundation

extension Platform {
    /// The Mac: the key in the Keychain, and in the app's UserDefaults when the
    /// Keychain refuses a locally built, ad-hoc signed app; the machine through
    /// the I/O Registry.
    static let current = Platform(
        signingKeyStore: FallbackSigningKeyStore(secure: KeychainSigningKeyStore(), fallback: DefaultsSigningKeyStore()),
        machineIdentity: IOKitMachineIdentity()
    )
}
#endif
