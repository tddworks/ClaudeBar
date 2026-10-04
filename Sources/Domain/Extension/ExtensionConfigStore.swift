import Quotas
import DataSources
import Providers
import Foundation
import Mockable

/// Reads and writes extension config values.
/// Non-secret values are persisted in settings JSON, secrets in UserDefaults.
@Mockable
public protocol ExtensionConfigRepository: Sendable {
    /// Reads a non-secret config value.
    func value(forFieldId fieldId: String, extensionId: String) -> String?

    /// Writes a non-secret config value. Pass nil to remove.
    func setValue(_ value: String?, forFieldId fieldId: String, extensionId: String)

    /// Reads a secret config value from secure storage.
    func secretValue(forFieldId fieldId: String, extensionId: String) -> String?

    /// Writes a secret config value to secure storage. Pass nil to remove.
    func setSecretValue(_ value: String?, forFieldId fieldId: String, extensionId: String)

    /// Returns all effective config values for an extension (stored + defaults),
    /// keyed by field ID. Used by ScriptProbe to build environment variables.
    func allValues(forExtensionId extensionId: String, fields: [ConfigField]) -> [String: String]
}
