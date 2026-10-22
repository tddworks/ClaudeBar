import Foundation
import Testing
@testable import Infrastructure
import Domain

/// A destination's secret: in the Keychain when a read-back proves it landed,
/// else in the app credential store — read Keychain first, removed from both.
@Suite
struct KeychainDestinationSecretsTests {
    /// Accepts every call and keeps nothing — the Keychain of an ad-hoc build.
    private final class RefusingKeychain: CredentialRepository, @unchecked Sendable {
        func save(_ value: String, forKey key: String) {}
        func get(forKey key: String) -> String? { nil }
        @discardableResult func delete(forKey key: String) -> Bool { true }
        func exists(forKey key: String) -> Bool { false }
    }

    private let suites = (keychain: "DestinationSecretsKeychain.\(UUID().uuidString)",
                          fallback: "DestinationSecretsFallback.\(UUID().uuidString)")
    private var keychain: UserDefaultsCredentialRepository {
        UserDefaultsCredentialRepository(defaults: UserDefaults(suiteName: suites.keychain)!)
    }
    private var fallback: UserDefaultsCredentialRepository {
        UserDefaultsCredentialRepository(defaults: UserDefaults(suiteName: suites.fallback)!)
    }

    private func cleanUp() {
        UserDefaults().removePersistentDomain(forName: suites.keychain)
        UserDefaults().removePersistentDomain(forName: suites.fallback)
    }

    @Test func `should keep a secret in the Keychain when it takes it`() {
        defer { cleanUp() }
        let secrets = KeychainDestinationSecrets(keychain: keychain, fallback: fallback)

        secrets.save("https://hooks.slack.com/x", forKey: "webhook-url-1")

        #expect(secrets.get(forKey: "webhook-url-1") == "https://hooks.slack.com/x")
        #expect(secrets.isInKeychain("webhook-url-1"))
        #expect(fallback.get(forKey: "webhook-url-1") == nil)
    }

    @Test func `should keep a secret in the app credential store when the Keychain refuses it`() {
        defer { cleanUp() }
        let secrets = KeychainDestinationSecrets(keychain: RefusingKeychain(), fallback: fallback)

        secrets.save("https://hooks.slack.com/x", forKey: "webhook-url-1")

        #expect(secrets.get(forKey: "webhook-url-1") == "https://hooks.slack.com/x")
        #expect(!secrets.isInKeychain("webhook-url-1"))
        #expect(fallback.get(forKey: "webhook-url-1") == "https://hooks.slack.com/x")
    }

    @Test func `should drop the fallback copy once the Keychain takes the secret`() {
        defer { cleanUp() }
        fallback.save("old", forKey: "webhook-url-1")
        let secrets = KeychainDestinationSecrets(keychain: keychain, fallback: fallback)

        secrets.save("new", forKey: "webhook-url-1")

        #expect(fallback.get(forKey: "webhook-url-1") == nil)
        #expect(secrets.get(forKey: "webhook-url-1") == "new")
    }

    @Test func `should read the Keychain's copy first`() {
        defer { cleanUp() }
        keychain.save("in keychain", forKey: "k")
        fallback.save("in fallback", forKey: "k")

        #expect(KeychainDestinationSecrets(keychain: keychain, fallback: fallback).get(forKey: "k") == "in keychain")
    }

    @Test func `should remove a secret from both stores`() {
        defer { cleanUp() }
        keychain.save("a", forKey: "k")
        fallback.save("b", forKey: "k")
        let secrets = KeychainDestinationSecrets(keychain: keychain, fallback: fallback)

        #expect(secrets.delete(forKey: "k"))
        #expect(secrets.get(forKey: "k") == nil)
    }
}
