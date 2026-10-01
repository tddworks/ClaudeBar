import Testing
import Foundation
@testable import Infrastructure

@Suite
struct DeepSeekSettingsRepositoryTests {
    @Test
    func `user defaults repository persists and removes DeepSeek settings`() {
        let suiteName = "DeepSeekSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

        #expect(repository.deepseekAuthEnvVar().isEmpty)
        #expect(repository.hasDeepSeekApiKey() == false)

        repository.setDeepSeekAuthEnvVar("CUSTOM_DEEPSEEK_KEY")
        repository.saveDeepSeekApiKey("sk-test")

        #expect(repository.deepseekAuthEnvVar() == "CUSTOM_DEEPSEEK_KEY")
        #expect(repository.getDeepSeekApiKey() == "sk-test")
        #expect(repository.hasDeepSeekApiKey() == true)

        repository.deleteDeepSeekApiKey()
        #expect(repository.getDeepSeekApiKey() == nil)
        #expect(repository.hasDeepSeekApiKey() == false)
    }

    @Test
    func `JSON repository persists and removes DeepSeek settings`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekJSONSettingsTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "DeepSeekJSONCredentialsTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
            credentials.removePersistentDomain(forName: suiteName)
        }
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials
        )

        #expect(repository.deepseekAuthEnvVar().isEmpty)
        #expect(repository.hasDeepSeekApiKey() == false)

        repository.setDeepSeekAuthEnvVar("CUSTOM_DEEPSEEK_KEY")
        repository.saveDeepSeekApiKey("sk-test")

        #expect(repository.deepseekAuthEnvVar() == "CUSTOM_DEEPSEEK_KEY")
        #expect(repository.getDeepSeekApiKey() == "sk-test")
        #expect(repository.hasDeepSeekApiKey() == true)

        repository.deleteDeepSeekApiKey()
        #expect(repository.getDeepSeekApiKey() == nil)
        #expect(repository.hasDeepSeekApiKey() == false)
    }
}
