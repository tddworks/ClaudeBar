#if os(Windows)
import Foundation

extension Platform {
    /// ClaudeBar for Windows so far (MODULAR_DESIGN §10): it counts and signs a
    /// day as the Mac does, and keeps no key and reads no machine yet. Phase 3
    /// keeps the key in Credential Manager and reads the machine GUID.
    static let current = Platform(signingKeyStore: nil, machineIdentity: nil)
}
#endif
