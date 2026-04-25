import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

@Suite
struct JSONExtensionConfigRepositoryTests {
    private func makeTempStore() -> (JSONExtensionConfigRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let settingsFile = tempDir.appendingPathComponent("settings.json")
        let store = JSONExtensionConfigRepository(
            settingsStore: JSONSettingsStore(fileURL: settingsFile),
            userDefaultsSuiteName: "com.claudebar.test.\(UUID().uuidString)"
        )
        return (store, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Non-Secret Values

    @Test
    func `stores and retrieves a string value`() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        store.setValue("https://api.example.com", forFieldId: "baseUrl", extensionId: "openrouter")
        let value = store.value(forFieldId: "baseUrl", extensionId: "openrouter")

        #expect(value == "https://api.example.com")
    }

    @Test
    func `returns nil for unset value`() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let value = store.value(forFieldId: "missing", extensionId: "openrouter")

        #expect(value == nil)
    }

    @Test
    func `isolates values between extensions`() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        store.setValue("value-a", forFieldId: "url", extensionId: "ext-a")
        store.setValue("value-b", forFieldId: "url", extensionId: "ext-b")

        #expect(store.value(forFieldId: "url", extensionId: "ext-a") == "value-a")
        #expect(store.value(forFieldId: "url", extensionId: "ext-b") == "value-b")
    }

    @Test
    func `removes value when set to nil`() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        store.setValue("something", forFieldId: "url", extensionId: "test")
        store.setValue(nil, forFieldId: "url", extensionId: "test")

        #expect(store.value(forFieldId: "url", extensionId: "test") == nil)
    }

    // MARK: - Secret Values

    @Test
    func `stores and retrieves a secret value via UserDefaults`() {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONExtensionConfigRepository(
            settingsStore: JSONSettingsStore(fileURL: tempDir.appendingPathComponent("settings.json")),
            userDefaultsSuiteName: suiteName
        )

        store.setSecretValue("sk-secret-123", forFieldId: "apiKey", extensionId: "openrouter")
        let value = store.secretValue(forFieldId: "apiKey", extensionId: "openrouter")

        #expect(value == "sk-secret-123")

        // Clean up UserDefaults
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test
    func `returns nil for unset secret`() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let value = store.secretValue(forFieldId: "apiKey", extensionId: "openrouter")

        #expect(value == nil)
    }

    @Test
    func `removes secret when set to nil`() {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONExtensionConfigRepository(
            settingsStore: JSONSettingsStore(fileURL: tempDir.appendingPathComponent("settings.json")),
            userDefaultsSuiteName: suiteName
        )

        store.setSecretValue("secret", forFieldId: "token", extensionId: "test")
        store.setSecretValue(nil, forFieldId: "token", extensionId: "test")

        #expect(store.secretValue(forFieldId: "token", extensionId: "test") == nil)

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    // MARK: - All Values (for env var injection)

    @Test
    func `allValues returns all stored values for an extension`() {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let store = JSONExtensionConfigRepository(
            settingsStore: JSONSettingsStore(fileURL: tempDir.appendingPathComponent("settings.json")),
            userDefaultsSuiteName: suiteName
        )

        let fields = [
            ConfigField(id: "baseUrl", label: "URL", type: .string),
            ConfigField(id: "apiKey", label: "Key", type: .secret),
            ConfigField(id: "budget", label: "Budget", type: .number, defaultValue: "100"),
        ]

        store.setValue("https://api.example.com", forFieldId: "baseUrl", extensionId: "test")
        store.setSecretValue("sk-123", forFieldId: "apiKey", extensionId: "test")
        // budget not set — should use default from field definition

        let values = store.allValues(forExtensionId: "test", fields: fields)

        #expect(values["baseUrl"] == "https://api.example.com")
        #expect(values["apiKey"] == "sk-123")
        #expect(values["budget"] == "100")
    }

    @Test
    func `allValues omits fields with no stored value and no default`() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let fields = [
            ConfigField(id: "optional", label: "Optional", type: .string),
        ]

        let values = store.allValues(forExtensionId: "test", fields: fields)

        #expect(values.isEmpty)
    }
}
