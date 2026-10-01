import Testing
import Foundation
@testable import Infrastructure

@Suite
struct ZaiSettingsRepositoryTests {
    @Test
    func `user defaults repository persists and removes Z.ai API key`() {
        let suiteName = "ZaiSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: suiteName + ".secure")!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: suiteName + ".secure")
        }
        let repository = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: UserDefaultsCredentialRepository(defaults: secureDefaults)
        )

        #expect(repository.hasZaiApiKey() == false)
        #expect(repository.getZaiApiKey() == nil)

        repository.saveZaiApiKey("glm-test-key")

        #expect(repository.getZaiApiKey() == "glm-test-key")
        #expect(repository.hasZaiApiKey() == true)

        repository.deleteZaiApiKey()
        #expect(repository.getZaiApiKey() == nil)
        #expect(repository.hasZaiApiKey() == false)
    }

    @Test
    func `JSON repository persists and removes Z.ai API key`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZaiJSONSettingsTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "ZaiJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: suiteName + ".secure")!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: suiteName + ".secure")
        }
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials,
            secureCredentials: UserDefaultsCredentialRepository(defaults: secureDefaults)
        )

        #expect(repository.hasZaiApiKey() == false)
        #expect(repository.getZaiApiKey() == nil)

        repository.saveZaiApiKey("glm-test-key")

        #expect(repository.getZaiApiKey() == "glm-test-key")
        #expect(repository.hasZaiApiKey() == true)

        repository.deleteZaiApiKey()
        #expect(repository.getZaiApiKey() == nil)
        #expect(repository.hasZaiApiKey() == false)
    }

    @Test
    func `JSON repository migrates a legacy Z.ai API key into secure storage`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZaiJSONMigrationTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "ZaiJSONLegacyTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: suiteName + ".secure")!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: suiteName + ".secure")
        }
        credentials.set("legacy-key", forKey: "com.claudebar.credentials.zai-api-key")

        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials,
            secureCredentials: UserDefaultsCredentialRepository(defaults: secureDefaults)
        )

        #expect(repository.getZaiApiKey() == "legacy-key")
        #expect(secureDefaults.string(forKey: "com.claudebar.credentials.zai-glm-api-key") == "legacy-key")
        #expect(credentials.string(forKey: "com.claudebar.credentials.zai-api-key") == nil)
    }

    @Test
    func `saving a new key replaces the previous Z.ai API key`() {
        let suiteName = "ZaiSettingsRepositoryReplaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: suiteName + ".secure")!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: suiteName + ".secure")
        }
        let repository = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: UserDefaultsCredentialRepository(defaults: secureDefaults)
        )

        repository.saveZaiApiKey("glm-old-key")
        repository.saveZaiApiKey("glm-new-key")

        #expect(repository.getZaiApiKey() == "glm-new-key")
    }
}
