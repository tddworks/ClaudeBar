import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

@Suite
struct DeepSeekCredentialMigrationTests {
    private struct RefusingStore: CredentialRepository {
        func save(_ value: String, forKey key: String) {}
        func get(forKey key: String) -> String? { nil }
        func delete(forKey key: String) -> Bool { false }
        func exists(forKey key: String) -> Bool { false }
    }

    @Test
    func `a legacy key migrates once and is shared by settings and the default vault scope`() {
        let suite = "DeepSeekMigration.\(UUID())"
        let legacy = UserDefaults(suiteName: suite)!
        let secure = UserDefaults(suiteName: suite + ".secure")!
        defer {
            legacy.removePersistentDomain(forName: suite)
            secure.removePersistentDomain(forName: suite + ".secure")
        }
        legacy.set("old-key", forKey: "com.claudebar.credentials.deepseek-api-key")
        let credentials = UserDefaultsCredentialRepository(defaults: secure)
        let vault = ProviderVault(credentials: credentials, legacyStore: legacy)
        #expect(vault.secret("apiKey", provider: "deepseek") == "old-key")
        #expect(credentials.get(forKey: "provider.deepseek.apiKey") == "old-key")
        #expect(legacy.object(forKey: "com.claudebar.credentials.deepseek-api-key") == nil)
        #expect(vault.secret("apiKey", provider: "deepseek.work") == nil)
        vault.save("work-key", "apiKey", provider: "deepseek.work")
        #expect(vault.secret("apiKey", provider: "deepseek.work") == "work-key")
        #expect(vault.secret("apiKey", provider: "deepseek") == "old-key")
        #expect(vault.delete("apiKey", provider: "deepseek.work"))
        #expect(vault.secret("apiKey", provider: "deepseek") == "old-key")
    }

    @Test
    func `a refused migration keeps the existing login and refuses destructive deletion`() {
        let suite = "DeepSeekFailedMigration.\(UUID())"
        let legacy = UserDefaults(suiteName: suite)!
        defer { legacy.removePersistentDomain(forName: suite) }
        legacy.set("old-key", forKey: "com.claudebar.credentials.deepseek-api-key")
        let vault = ProviderVault(credentials: RefusingStore(), legacyStore: legacy)
        #expect(vault.secret("apiKey", provider: "deepseek") == "old-key")
        #expect(vault.secret("apiKey", provider: "deepseek.work") == nil)
        #expect(vault.delete("apiKey", provider: "deepseek") == false)
        #expect(legacy.string(forKey: "com.claudebar.credentials.deepseek-api-key") == "old-key")
    }
}
