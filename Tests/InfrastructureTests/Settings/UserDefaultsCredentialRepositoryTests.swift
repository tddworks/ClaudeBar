import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("UserDefaultsCredentialRepository Tests")
struct UserDefaultsCredentialRepositoryTests {

    // Use a unique suite name to avoid conflicts with other tests
    private let testSuiteName = "com.claudebar.test.credentials.\(UUID().uuidString)"

    private func makeRepository() -> UserDefaultsCredentialRepository {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        return UserDefaultsCredentialRepository(defaults: defaults)
    }

    private func cleanupDefaults() {
        UserDefaults().removePersistentDomain(forName: testSuiteName)
    }

    // MARK: - Save Tests

    @Test
    func `should keep a saved credential`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        repository.save("test-token", forKey: "test-key")

        // Then
        let retrieved = repository.get(forKey: "test-key")
        #expect(retrieved == "test-token")
    }

    @Test
    func `should replace a credential saved again`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.save("old-token", forKey: "test-key")

        // When
        repository.save("new-token", forKey: "test-key")

        // Then
        let retrieved = repository.get(forKey: "test-key")
        #expect(retrieved == "new-token")
    }

    @Test
    func `should keep a credential saved as empty text`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        repository.save("", forKey: "test-key")

        // Then
        let retrieved = repository.get(forKey: "test-key")
        #expect(retrieved == "")
    }

    // MARK: - Get Tests

    @Test
    func `should have no credential that was never saved`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        let retrieved = repository.get(forKey: "non-existent-key")

        // Then
        #expect(retrieved == nil)
    }

    @Test
    func `should give back the credential that was saved`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.save("my-secret-token", forKey: "github-token")

        // When
        let retrieved = repository.get(forKey: "github-token")

        // Then
        #expect(retrieved == "my-secret-token")
    }

    // MARK: - Delete Tests

    @Test
    func `should forget a credential once it is removed`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.save("to-be-deleted", forKey: "delete-key")

        // When
        repository.delete(forKey: "delete-key")

        // Then
        let retrieved = repository.get(forKey: "delete-key")
        #expect(retrieved == nil)
    }

    @Test
    func `should quietly remove a credential that was never saved`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When/Then - should not throw
        repository.delete(forKey: "non-existent-key")

        #expect(repository.get(forKey: "non-existent-key") == nil)
    }

    // MARK: - Exists Tests

    @Test
    func `should not count a credential that was never saved as present`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        let exists = repository.exists(forKey: "non-existent")

        // Then
        #expect(exists == false)
    }

    @Test
    func `should count a saved credential as present`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.save("some-value", forKey: "exists-key")

        // When
        let exists = repository.exists(forKey: "exists-key")

        // Then
        #expect(exists == true)
    }

    @Test
    func `should not count a removed credential as present`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }
        repository.save("temp-value", forKey: "temp-key")
        repository.delete(forKey: "temp-key")

        // When
        let exists = repository.exists(forKey: "temp-key")

        // Then
        #expect(exists == false)
    }

    // MARK: - Integration Tests

    @Test
    func `should keep, replace and forget a credential over its whole life`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // Initially doesn't exist
        #expect(repository.exists(forKey: "lifecycle-key") == false)
        #expect(repository.get(forKey: "lifecycle-key") == nil)

        // Save
        repository.save("lifecycle-value", forKey: "lifecycle-key")
        #expect(repository.exists(forKey: "lifecycle-key") == true)
        #expect(repository.get(forKey: "lifecycle-key") == "lifecycle-value")

        // Update
        repository.save("updated-value", forKey: "lifecycle-key")
        #expect(repository.get(forKey: "lifecycle-key") == "updated-value")

        // Delete
        repository.delete(forKey: "lifecycle-key")
        #expect(repository.exists(forKey: "lifecycle-key") == false)
        #expect(repository.get(forKey: "lifecycle-key") == nil)
    }

    @Test
    func `should keep each credential apart from the others`() {
        // Given
        let repository = makeRepository()
        defer { cleanupDefaults() }

        // When
        repository.save("value1", forKey: "key1")
        repository.save("value2", forKey: "key2")
        repository.delete(forKey: "key1")

        // Then
        #expect(repository.get(forKey: "key1") == nil)
        #expect(repository.get(forKey: "key2") == "value2")
    }
}
