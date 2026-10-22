import Foundation
import Testing
import Domain
@testable import Infrastructure

/// *Rules*' repository: the rules file is plaintext and the webhook URL is a
/// secret in the vault, with the fallback Notify! keeps when a Keychain
/// refuses ([design](docs/features/alerting/rules/design.md)).
@Suite
struct JSONRuleRepositoryTests {
    /// A secure store that holds an older URL and refuses to replace or remove
    /// it — a Keychain ACL that allows reads while denying updates and deletes,
    /// which is the state the fallback exists for.
    private final class StaleSecure: CredentialRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?

        init(holding value: String?) { self.value = value }

        func save(_ value: String, forKey key: String) { /* refused */ }
        func get(forKey key: String) -> String? { lock.withLock { value } }
        @discardableResult func delete(forKey key: String) -> Bool { false /* refused */ }
        func exists(forKey key: String) -> Bool { lock.withLock { value != nil } }
    }

    /// Where a refused URL goes, and what the repository reads it back from.
    private final class RecordingFallback: CredentialRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func save(_ value: String, forKey key: String) { lock.withLock { values[key] = value } }
        func get(forKey key: String) -> String? { lock.withLock { values[key] } }
        @discardableResult func delete(forKey key: String) -> Bool {
            lock.withLock { values[key] = nil }
            return true
        }
        func exists(forKey key: String) -> Bool { lock.withLock { values[key] != nil } }
    }

    /// A repository over a throwaway rules file and the two stores given.
    private func repository(
        secure: any CredentialRepository,
        fallback: any CredentialRepository
    ) -> JSONRuleRepository {
        JSONRuleRepository(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("rules-\(UUID().uuidString).json"),
            secureCredentials: secure,
            fallbackCredentials: fallback
        )
    }

    /// A URL the Keychain refuses falls back to the app store, which wins.
    @Test func `should keep the URL the person just gave when the Keychain refuses it`() {
        let secure = StaleSecure(holding: "https://old.test/hook")
        let fallback = RecordingFallback()
        let repository = repository(secure: secure, fallback: fallback)

        repository.setWebhookURL("https://new.test/hook", forRule: "rule-1")

        #expect(repository.webhookURL(forRule: "rule-1") == "https://new.test/hook")
    }

    /// A removal the Keychain refuses is tombstoned in the fallback.
    @Test func `should forget a URL the Keychain refuses to forget when the person removes it`() {
        let secure = StaleSecure(holding: "https://old.test/hook")
        let repository = repository(secure: secure, fallback: RecordingFallback())

        repository.setWebhookURL(nil, forRule: "rule-1")

        #expect(repository.webhookURL(forRule: "rule-1") == nil)
    }
}