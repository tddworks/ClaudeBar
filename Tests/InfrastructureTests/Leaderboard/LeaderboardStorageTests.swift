import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

/// The membership's record in `settings.json`, and the private key beside the
/// other secrets — in the Keychain, or the fallback store when the Keychain
/// refuses a locally built app.
@Suite
struct LeaderboardStorageTests {
    /// A credential store that keeps what it's given.
    private final class KeepingCredentials: CredentialRepository, @unchecked Sendable {
        var values: [String: String] = [:]
        func save(_ value: String, forKey key: String) { values[key] = value }
        func get(forKey key: String) -> String? { values[key] }
        @discardableResult func delete(forKey key: String) -> Bool { values[key] = nil; return true }
        func exists(forKey key: String) -> Bool { values[key] != nil }
    }

    /// The Keychain as an ad-hoc signed build sees it: every call "succeeds", nothing is kept.
    private final class RefusingCredentials: CredentialRepository, @unchecked Sendable {
        func save(_ value: String, forKey key: String) {}
        func get(forKey key: String) -> String? { nil }
        @discardableResult func delete(forKey key: String) -> Bool { true }
        func exists(forKey key: String) -> Bool { false }
    }

    private func repository() -> (JSONSettingsRepository, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/settings.json")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return (JSONSettingsRepository(store: JSONSettingsStore(fileURL: url), credentials: defaults,
                                       secureCredentials: KeepingCredentials()), url)
    }

    // MARK: - Settings

    @Test func `a membership is kept and read back`() {
        let (settings, _) = repository()
        let record = LeaderboardRecord(username: "tokenwhale", sharing: ["codex", "claude"], visible: false,
                                       lastUpload: Date(timeIntervalSince1970: 1_791_080_000))

        settings.saveLeaderboardRecord(record)

        #expect(settings.leaderboardRecord() == record)
    }

    @Test func `forgetting a membership leaves nothing behind`() throws {
        let (settings, url) = repository()
        settings.saveLeaderboardRecord(LeaderboardRecord(username: "tokenwhale", sharing: ["claude"], visible: true, lastUpload: nil))

        settings.saveLeaderboardRecord(nil)

        #expect(settings.leaderboardRecord() == nil)
        #expect(try !String(contentsOf: url, encoding: .utf8).contains("tokenwhale"))
    }

    // MARK: - The key

    @Test func `the key goes to the Keychain when it takes it`() {
        let secure = KeepingCredentials()
        let fallback = KeepingCredentials()
        let store = CredentialSigningKeyStore(secure: secure, fallback: fallback)

        store.save(Data([1, 2, 3]))

        #expect(store.load() == Data([1, 2, 3]))
        #expect(secure.values.count == 1)
        #expect(fallback.values.isEmpty)
        #expect(store.isSecure)
    }

    @Test func `a Keychain that refuses leaves the key in the fallback store`() {
        let fallback = KeepingCredentials()
        let store = CredentialSigningKeyStore(secure: RefusingCredentials(), fallback: fallback)

        store.save(Data([1, 2, 3]))

        #expect(store.load() == Data([1, 2, 3]))
        #expect(fallback.values.count == 1)
        #expect(!store.isSecure)
    }

    @Test func `deleting the key clears both stores`() {
        let secure = KeepingCredentials()
        let fallback = KeepingCredentials()
        secure.values[CredentialKey.leaderboardSigningKey] = Data([9]).base64EncodedString()
        fallback.values[CredentialKey.leaderboardSigningKey] = Data([8]).base64EncodedString()
        let store = CredentialSigningKeyStore(secure: secure, fallback: fallback)

        store.delete()

        #expect(store.load() == nil)
        #expect(secure.values.isEmpty && fallback.values.isEmpty)
    }
}
