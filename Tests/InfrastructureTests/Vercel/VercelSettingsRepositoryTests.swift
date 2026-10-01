import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct VercelSettingsRepositoryTests {
    @Test
    func `user defaults repository persists and removes Vercel settings`() {
        let suiteName = "VercelSettingsRepositoryTests.\(UUID().uuidString)"
        let secureSuiteName = "VercelSecureCredentialsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: secureSuiteName)!
        let secureCredentials = UserDefaultsCredentialRepository(defaults: secureDefaults)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: secureSuiteName)
        }
        let repository = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: secureCredentials
        )

        #expect(repository.vercelAuthEnvVar().isEmpty)
        #expect(repository.hasVercelApiKey() == false)

        repository.setVercelAuthEnvVar("CUSTOM_VERCEL_KEY")
        repository.saveVercelApiKey("vck_test")

        #expect(repository.vercelAuthEnvVar() == "CUSTOM_VERCEL_KEY")
        #expect(repository.getVercelApiKey() == "vck_test")
        #expect(repository.hasVercelApiKey() == true)
        #expect(secureCredentials.get(forKey: CredentialKey.vercelApiKey) == "vck_test")
        #expect(defaults.object(forKey: "com.claudebar.credentials.vercel-api-key") == nil)

        #expect(repository.deleteVercelApiKey() == true)
        #expect(repository.getVercelApiKey() == nil)
        #expect(repository.hasVercelApiKey() == false)
    }

    @Test
    func `JSON repository persists and removes Vercel settings`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VercelJSONSettingsTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "VercelJSONCredentialsTests.\(UUID().uuidString)"
        let secureSuiteName = "VercelJSONSecureCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: secureSuiteName)!
        let secureCredentials = UserDefaultsCredentialRepository(defaults: secureDefaults)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: secureSuiteName)
        }
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials,
            secureCredentials: secureCredentials
        )

        #expect(repository.vercelAuthEnvVar().isEmpty)
        #expect(repository.hasVercelApiKey() == false)

        repository.setVercelAuthEnvVar("CUSTOM_VERCEL_KEY")
        repository.saveVercelApiKey("vck_test")

        #expect(repository.vercelAuthEnvVar() == "CUSTOM_VERCEL_KEY")
        #expect(repository.getVercelApiKey() == "vck_test")
        #expect(repository.hasVercelApiKey() == true)
        #expect(secureCredentials.get(forKey: CredentialKey.vercelApiKey) == "vck_test")
        #expect(credentials.object(forKey: "com.claudebar.credentials.vercel-api-key") == nil)

        #expect(repository.deleteVercelApiKey() == true)
        #expect(repository.getVercelApiKey() == nil)
        #expect(repository.hasVercelApiKey() == false)
    }

    @Test
    func `user defaults repository migrates legacy Vercel API key`() {
        let suiteName = "VercelLegacySettingsTests.\(UUID().uuidString)"
        let secureSuiteName = "VercelLegacySecureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: secureSuiteName)!
        let secureCredentials = UserDefaultsCredentialRepository(defaults: secureDefaults)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: secureSuiteName)
        }
        defaults.set("legacy-key", forKey: "com.claudebar.credentials.vercel-api-key")
        let repository = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: secureCredentials
        )

        #expect(repository.getVercelApiKey() == "legacy-key")
        #expect(secureCredentials.get(forKey: CredentialKey.vercelApiKey) == "legacy-key")
        #expect(defaults.object(forKey: "com.claudebar.credentials.vercel-api-key") == nil)
    }

    @Test
    func `user defaults repository preserves legacy Vercel API key when secure migration fails`() {
        let suiteName = "VercelFailedMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-key", forKey: "com.claudebar.credentials.vercel-api-key")
        let repository = UserDefaultsProviderSettingsRepository(
            userDefaults: defaults,
            secureCredentials: FailingCredentialRepository()
        )

        #expect(repository.getVercelApiKey() == "legacy-key")
        #expect(defaults.string(forKey: "com.claudebar.credentials.vercel-api-key") == "legacy-key")
    }

    @Test
    func `JSON repository migrates legacy Vercel API key`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VercelLegacyJSONTests.\(UUID().uuidString)")
        let suiteName = "VercelLegacyJSONCredentialsTests.\(UUID().uuidString)"
        let secureSuiteName = "VercelLegacyJSONSecureTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        let secureDefaults = UserDefaults(suiteName: secureSuiteName)!
        let secureCredentials = UserDefaultsCredentialRepository(defaults: secureDefaults)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
            secureDefaults.removePersistentDomain(forName: secureSuiteName)
        }
        credentials.set("legacy-key", forKey: "com.claudebar.credentials.vercel-api-key")
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: tempDirectory.appendingPathComponent("settings.json")),
            credentials: credentials,
            secureCredentials: secureCredentials
        )

        #expect(repository.getVercelApiKey() == "legacy-key")
        #expect(secureCredentials.get(forKey: CredentialKey.vercelApiKey) == "legacy-key")
        #expect(credentials.object(forKey: "com.claudebar.credentials.vercel-api-key") == nil)
    }

    @Test
    func `JSON repository preserves legacy Vercel API key when secure migration fails`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VercelFailedMigrationJSONTests.\(UUID().uuidString)")
        let suiteName = "VercelFailedMigrationJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
        }
        credentials.set("legacy-key", forKey: "com.claudebar.credentials.vercel-api-key")
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: tempDirectory.appendingPathComponent("settings.json")),
            credentials: credentials,
            secureCredentials: FailingCredentialRepository()
        )

        #expect(repository.getVercelApiKey() == "legacy-key")
        #expect(credentials.string(forKey: "com.claudebar.credentials.vercel-api-key") == "legacy-key")
    }

    @Test
    func `failed secure overwrite preserves the legacy Vercel API key`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VercelFailedOverwriteJSONTests.\(UUID().uuidString)")
        let suiteName = "VercelFailedOverwriteJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
        }
        credentials.set("legacy-key", forKey: "com.claudebar.credentials.vercel-api-key")
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: tempDirectory.appendingPathComponent("settings.json")),
            credentials: credentials,
            secureCredentials: FailingCredentialRepository(storedValue: "stale-secure-key")
        )

        repository.saveVercelApiKey("replacement-key")

        #expect(credentials.string(forKey: "com.claudebar.credentials.vercel-api-key") == "legacy-key")
    }

    @Test
    func `secure deletion failure is reported and retains the Vercel API key`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VercelFailedDeleteJSONTests.\(UUID().uuidString)")
        let suiteName = "VercelFailedDeleteJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
        }
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: tempDirectory.appendingPathComponent("settings.json")),
            credentials: credentials,
            secureCredentials: FailingCredentialRepository(storedValue: "stored-key")
        )

        #expect(repository.deleteVercelApiKey() == false)
        #expect(repository.getVercelApiKey() == "stored-key")
    }
}

private struct FailingCredentialRepository: CredentialRepository {
    let storedValue: String?

    init(storedValue: String? = nil) {
        self.storedValue = storedValue
    }

    func save(_: String, forKey _: String) {}
    func get(forKey _: String) -> String? { storedValue }
    func delete(forKey _: String) -> Bool { false }
    func exists(forKey _: String) -> Bool { storedValue != nil }
}
