import Domain
import Foundation

/// Extensions became definitions (docs/features/providers/extensions/design.md). What a person saved
/// for one moves once, by the same names: a value from
/// `extensions.<id>.<field>` into the provider's settings, a secret from
/// UserDefaults into the vault (the Keychain) — and out of UserDefaults.
/// Recorded per extension, so a later change is never overwritten.
public enum ExtensionSettingsUpgrade {
    static let done = "upgradedFromExtension"

    public static func run(_ definitions: [ProviderDefinition], store: JSONSettingsStore,
                           settings: any ProviderSettingsRepository, vault: any SecretVault,
                           defaults: UserDefaults = .standard) {
        for definition in definitions where definition.profile.origin == .extension {
            guard settings.isOn(done, forProvider: definition.id) != true else { continue }
            let extensionId = String(definition.id.dropFirst("ext-".count))
            for setting in definition.settings {
                if setting.kind == .secret {
                    let key = "com.claudebar.credentials.ext-\(extensionId)-\(setting.id)"
                    if let value = defaults.string(forKey: key), !value.isEmpty {
                        vault.save(value, setting.id, provider: definition.id)
                        defaults.removeObject(forKey: key)
                    }
                } else if let value: String = store.read(key: "extensions.\(extensionId).\(setting.id)") {
                    settings.setValue(value, setting.id, forProvider: definition.id)
                }
            }
            settings.setOn(true, done, forProvider: definition.id)
            AppLog.providers.info("Extension \(extensionId): its saved settings now belong to its definition")
        }
    }
}
