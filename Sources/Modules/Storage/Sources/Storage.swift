import Foundation
import DataSources
import Providers

/// The factory: the settings file and the vault, handed out as their ports,
/// so no caller names an implementation.
public enum Storage {
    /// The person's own settings file, `~/.claudebar/settings.json`.
    public static let settings: any SettingsFile = JSONSettingsRepository(store: .shared)

    /// Settings kept in `fileURL`: a test's own file, never the person's. With
    /// `secretsIn`, secrets go to those defaults instead of the Keychain.
    public static func makeSettings(fileURL: URL, secretsIn defaults: UserDefaults? = nil) -> any SettingsFile {
        guard let defaults else { return JSONSettingsRepository(store: JSONSettingsStore(fileURL: fileURL)) }
        return JSONSettingsRepository(store: JSONSettingsStore(fileURL: fileURL), credentials: defaults,
                                      secureCredentials: UserDefaultsCredentialRepository(defaults: defaults))
    }

    /// Where a provider's secrets are kept: the Keychain, then the old store.
    /// With `secretsIn`, those defaults instead: a test's own, never the Keychain.
    public static func makeVault(secretsIn defaults: UserDefaults? = nil) -> any SecretVault {
        guard let defaults else { return ProviderVault() }
        return ProviderVault(credentials: UserDefaultsCredentialRepository(defaults: defaults), legacyStore: defaults)
    }

    /// What was saved for an extension before it was a definition moves once.
    public static func upgradeExtensionSettings(_ definitions: [ProviderDefinition],
                                                settings: any ProviderSettingsRepository,
                                                vault: any SecretVault) {
        ExtensionSettingsUpgrade.run(definitions, store: .shared, settings: settings, vault: vault)
    }
}
