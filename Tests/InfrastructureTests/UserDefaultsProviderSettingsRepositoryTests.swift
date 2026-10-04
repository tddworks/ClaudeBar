import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("UserDefaultsProviderSettingsRepository Tests")
struct UserDefaultsProviderSettingsRepositoryTests {

    // Use a unique suite name to avoid conflicts with other tests
    private let testSuiteName = "com.claudebar.test.settings.\(UUID().uuidString)"

    private func makeRepository() -> UserDefaultsProviderSettingsRepository {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        return UserDefaultsProviderSettingsRepository(userDefaults: defaults)
    }

    private func cleanupDefaults() {
        UserDefaults().removePersistentDomain(forName: testSuiteName)
    }

    // MARK: - isEnabled Tests

    @Test
    func `isEnabled returns default value when not set`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        let enabledWithTrueDefault = repository.isEnabled(forProvider: "claude", defaultValue: true)
        let enabledWithFalseDefault = repository.isEnabled(forProvider: "codex", defaultValue: false)

        // Then
        #expect(enabledWithTrueDefault == true)
        #expect(enabledWithFalseDefault == false)
    }

    @Test
    func `isEnabled returns stored value when set`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setEnabled(true, forProvider: "claude")

        // When
        let enabled = repository.isEnabled(forProvider: "claude", defaultValue: false)

        // Then
        #expect(enabled == true)
    }

    @Test
    func `isEnabled returns false when explicitly set to false`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.setEnabled(false, forProvider: "claude")

        // When
        let enabled = repository.isEnabled(forProvider: "claude", defaultValue: true)

        // Then
        #expect(enabled == false)
    }

    // MARK: - setEnabled Tests

    @Test
    func `setEnabled persists value`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        repository.setEnabled(true, forProvider: "gemini")

        // Then
        let enabled = repository.isEnabled(forProvider: "gemini", defaultValue: false)
        #expect(enabled == true)
    }

    @Test
    func `setEnabled can toggle value`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        repository.setEnabled(true, forProvider: "copilot")
        let enabledFirst = repository.isEnabled(forProvider: "copilot", defaultValue: false)

        repository.setEnabled(false, forProvider: "copilot")
        let enabledSecond = repository.isEnabled(forProvider: "copilot", defaultValue: true)

        // Then
        #expect(enabledFirst == true)
        #expect(enabledSecond == false)
    }

    // MARK: - Provider Isolation Tests

    @Test
    func `settings are isolated per provider`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        repository.setEnabled(true, forProvider: "claude")
        repository.setEnabled(false, forProvider: "codex")

        // Then
        #expect(repository.isEnabled(forProvider: "claude", defaultValue: false) == true)
        #expect(repository.isEnabled(forProvider: "codex", defaultValue: true) == false)
        #expect(repository.isEnabled(forProvider: "gemini", defaultValue: true) == true) // Uses default
    }

    // MARK: - Persistence Tests

    @Test
    func `values persist across repository instances`() {
        // Given
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defer { cleanupDefaults() }

        let repository1 = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repository1.setEnabled(true, forProvider: "antigravity")

        // When
        let repository2 = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        let enabled = repository2.isEnabled(forProvider: "antigravity", defaultValue: false)

        // Then
        #expect(enabled == true)
    }

    // MARK: - Hidden Quota Keys (issue #140)

    @Test
    func `hiddenQuotaKeys defaults to empty`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        #expect(repository.hiddenQuotaKeys(forProvider: "gemini") == [])
    }

    @Test
    func `setHiddenQuotaKeys persists across repository instances`() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defer { cleanupDefaults() }

        let repository1 = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repository1.setHiddenQuotaKeys(["model:gemini-2.0-flash"], forProvider: "gemini")

        let repository2 = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

        #expect(repository2.hiddenQuotaKeys(forProvider: "gemini") == ["model:gemini-2.0-flash"])
    }

    @Test
    func `hiddenQuotaKeys is per provider`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setHiddenQuotaKeys(["model:gemini-2.0-flash"], forProvider: "gemini")
        repository.setHiddenQuotaKeys(["weekly"], forProvider: "codex")

        #expect(repository.hiddenQuotaKeys(forProvider: "gemini") == ["model:gemini-2.0-flash"])
        #expect(repository.hiddenQuotaKeys(forProvider: "codex") == ["weekly"])
        #expect(repository.hiddenQuotaKeys(forProvider: "claude") == [])
    }

    @Test
    func `setHiddenQuotaKeys with empty set clears the stored keys`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setHiddenQuotaKeys(["model:gemini-2.0-flash"], forProvider: "gemini")
        repository.setHiddenQuotaKeys([], forProvider: "gemini")

        #expect(repository.hiddenQuotaKeys(forProvider: "gemini") == [])
    }

    // MARK: - Claude CLI Fallback

    @Test
    func `claudeCliFallbackEnabled defaults to true`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        #expect(repository.claudeCliFallbackEnabled() == true)
    }

    @Test
    func `setClaudeCliFallbackEnabled persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setClaudeCliFallbackEnabled(false)
        #expect(repository.claudeCliFallbackEnabled() == false)
    }

    // MARK: - Codex Verified Flag

    @Test
    func `codexVerifiedAtLeastOnce defaults to false`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        #expect(repository.codexVerifiedAtLeastOnce() == false)
    }

    @Test
    func `setCodexVerifiedAtLeastOnce persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setCodexVerifiedAtLeastOnce(true)
        #expect(repository.codexVerifiedAtLeastOnce() == true)

        repository.setCodexVerifiedAtLeastOnce(false)
        #expect(repository.codexVerifiedAtLeastOnce() == false)
    }

    // MARK: - Provider Order

    @Test
    func `providerOrder defaults to empty`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        #expect(repository.providerOrder() == [])
    }

    @Test
    func `setProviderOrder persists value`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setProviderOrder(["gemini", "claude", "codex"])

        // Read back through a fresh repository over the same suite, so the
        // value really landed in the persistent store.
        let reloaded = makeRepository()
        #expect(reloaded.providerOrder() == ["gemini", "claude", "codex"])
    }

    @Test
    func `setProviderOrder empty clears the stored order`() {
        let repository = makeRepository()
        defer { cleanupDefaults() }

        repository.setProviderOrder(["gemini", "claude", "codex"])
        repository.setProviderOrder([])
        #expect(repository.providerOrder() == [])
    }
}
