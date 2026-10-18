import Testing
import Foundation
@testable import Infrastructure

@Suite
struct DeepSeekSettingsRepositoryTests {
    @Test
    func `should remember and forget the DeepSeek key and its environment variable when settings live in settings.json`() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekJSONSettingsTests.\(UUID().uuidString)")
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let suiteName = "DeepSeekJSONCredentialsTests.\(UUID().uuidString)"
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
