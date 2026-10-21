import Foundation
import Testing
import Domain
@testable import Infrastructure

/// *Rules*' repository: the rules file is plaintext and the webhook URL is a
/// secret in the vault, with the fallback Notify! keeps when a Keychain
/// refuses ([design](docs/features/alerting/rules/design.md)).
@Suite
struct JSONRuleRepositoryTests {
    /// A secure store that holds an older URL and refuses to replace it — the
    /// Keychain of a locally built, ad-hoc signed app.
    private final class StaleSecure: CredentialRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?

        init(holding value: String?) { self.value = value }

        func save(_ value: String, forKey key: String) { /* refused */ }
        func get(forKey key: String) -> String? { lock.withLock { value } }
        @discardableResult func delete(forKey key: String) -> Bool {
            lock.withLock { value = nil }
            return true
        }
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

    @Test func `should keep the URL the person just gave when the Keychain refuses it`() {
        let secure = StaleSecure(holding: "https://old.test/hook")
        let fallback = RecordingFallback()
        let repository = repository(secure: secure, fallback: fallback)

        repository.setWebhookURL("https://new.test/hook", forRule: "rule-1")

        #expect(repository.webhookURL(forRule: "rule-1") == "https://new.test/hook")
    }
}