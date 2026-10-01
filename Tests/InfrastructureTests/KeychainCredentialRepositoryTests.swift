import Testing
import Foundation
@testable import Infrastructure

@Suite(.serialized)
struct KeychainCredentialRepositoryTests {
    @Test
    func `saves updates retrieves and deletes a credential`() {
        let key = "credential-\(UUID().uuidString)"
        let repository = KeychainCredentialRepository(
            service: "com.tddworks.claudebar.tests.\(UUID().uuidString)"
        )
        defer { _ = repository.delete(forKey: key) }

        #expect(repository.get(forKey: key) == nil)
        #expect(repository.exists(forKey: key) == false)

        repository.save("first-value", forKey: key)
        #expect(repository.get(forKey: key) == "first-value")
        #expect(repository.exists(forKey: key) == true)

        repository.save("updated-value", forKey: key)
        #expect(repository.get(forKey: key) == "updated-value")

        #expect(repository.delete(forKey: key) == true)
        #expect(repository.get(forKey: key) == nil)
        #expect(repository.exists(forKey: key) == false)
    }

    @Test
    func `deleting a missing credential is idempotent`() {
        let repository = KeychainCredentialRepository(
            service: "com.tddworks.claudebar.tests.\(UUID().uuidString)"
        )

        #expect(repository.delete(forKey: "missing") == true)

        #expect(repository.get(forKey: "missing") == nil)
    }
}
