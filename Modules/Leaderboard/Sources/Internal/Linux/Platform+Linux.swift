#if os(Linux)
import Foundation

extension Platform {
    /// Linux: the key in the person's secret store through libsecret, and in
    /// the app's own store when that refuses it; the machine labelled as
    /// `LinuxMachineIdentity` says.
    static let current = Platform(
        deviceName: "Linux",
        signingKeyStore: FallbackSigningKeyStore(secure: SecretToolSigningKeyStore(),
                                                 fallback: DefaultsSigningKeyStore()),
        machineIdentity: LinuxMachineIdentity()
    )
}
#endif
