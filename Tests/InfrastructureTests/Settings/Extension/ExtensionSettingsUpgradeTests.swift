import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

/// Extensions become definitions (docs/features/providers/extensions/design.md): what a person saved
/// for an extension moves once — values into the provider's settings,
/// secrets from UserDefaults into the vault.
@Suite
struct ExtensionSettingsUpgradeTests {
    private final class Vault: SecretVault, @unchecked Sendable {
        var saved: [String: String] = [:]
        func secret(_ name: String, provider: String) -> String? { saved["\(provider).\(name)"] }
        func save(_ value: String, _ name: String, provider: String) { saved["\(provider).\(name)"] = value }
        func delete(_ name: String, provider: String) -> Bool { saved.removeValue(forKey: "\(provider).\(name)") != nil }
    }

    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ext-upgrade-\(UUID().uuidString)")
    private let suite = "ext-upgrade-\(UUID().uuidString)"

    private func definition() throws -> ProviderDefinition {
        try Extensions.definition(manifest: Data("""
        {"id":"acme","name":"Acme","version":"1",
         "config":[{"id":"apiKey","label":"API Key","type":"secret"},{"id":"region","label":"Region","type":"string"}],
         "sections":[{"id":"quotas","type":"quotaGrid","probe":{"command":"./probe.sh"}}]}
        """.utf8), folder: temp)
    }

    @Test
    func `should keep an extension's saved value in its provider settings and its secret in the vault after the upgrade`() throws {
        let store = JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json"))
        let settings = JSONSettingsRepository(store: store)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        store.write(value: "eu", key: "extensions.acme.region")
        defaults.set("sk-1", forKey: "com.claudebar.credentials.ext-acme-apiKey")
        let vault = Vault()

        ExtensionSettingsUpgrade.run([try definition()], store: store, settings: settings, vault: vault, defaults: defaults)

        #expect(settings.value("region", forProvider: "ext-acme") == "eu")
        #expect(vault.secret("apiKey", provider: "ext-acme") == "sk-1")
        #expect(defaults.string(forKey: "com.claudebar.credentials.ext-acme-apiKey") == nil)
    }

    @Test
    func `should keep the person's later change when the extension upgrade runs again`() throws {
        let store = JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json"))
        let settings = JSONSettingsRepository(store: store)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        store.write(value: "eu", key: "extensions.acme.region")
        ExtensionSettingsUpgrade.run([try definition()], store: store, settings: settings, vault: Vault(), defaults: defaults)
        settings.setValue("us", "region", forProvider: "ext-acme")

        ExtensionSettingsUpgrade.run([try definition()], store: store, settings: settings, vault: Vault(), defaults: defaults)

        #expect(settings.value("region", forProvider: "ext-acme") == "us")
    }
}
