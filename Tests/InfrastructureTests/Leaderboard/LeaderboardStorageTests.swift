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

    @Test func `should remember the leaderboard membership across reads`() {
        let (settings, _) = repository()
        let record = LeaderboardRecord(username: "tokenwhale", sharing: ["codex", "claude"], visible: false,
                                       lastUpload: Date(timeIntervalSince1970: 1_791_080_000),
                                       sharesCountry: true, globeHintDismissed: true,
                                       link: ProfileLink(platform: .instagram, handle: "boxcee.codes"))

        settings.saveLeaderboardRecord(record)

        #expect(settings.leaderboardRecord() == record)
    }

    @Test func `should remember the days the server refused after a relaunch`() {
        let (settings, url) = repository()
        let refused = [RefusedDay(provider: "claude", day: "2026-10-04", reason: "cap")]
        settings.saveLeaderboardRecord(LeaderboardRecord(username: "tokenwhale", sharing: ["claude"], visible: true,
                                                         lastUpload: nil, refused: refused))

        let relaunched = JSONSettingsRepository(store: JSONSettingsStore(fileURL: url), credentials: UserDefaults(suiteName: UUID().uuidString)!,
                                                secureCredentials: KeepingCredentials())

        #expect(relaunched.leaderboardRecord()?.refused == refused)
    }

    @Test func `should leave nothing of the membership in settings when it is forgotten`() throws {
        let (settings, url) = repository()
        settings.saveLeaderboardRecord(LeaderboardRecord(username: "tokenwhale", sharing: ["claude"], visible: true, lastUpload: nil))

        settings.saveLeaderboardRecord(nil)

        #expect(settings.leaderboardRecord() == nil)
        #expect(try !String(contentsOf: url, encoding: .utf8).contains("tokenwhale"))
    }

    @Test func `should remember the Leaderboard is off, apart from the membership`() {
        let (settings, _) = repository()
        settings.saveLeaderboardRecord(LeaderboardRecord(username: "tokenwhale", sharing: ["claude"], visible: true, lastUpload: nil))

        settings.setLeaderboardOn(false)
        settings.saveLeaderboardRecord(nil)

        #expect(!settings.isLeaderboardOn())
    }

    @Test func `should count the Leaderboard as on when nothing was saved`() {
        let (settings, _) = repository()

        #expect(settings.isLeaderboardOn())
    }

    // MARK: - The key

    @Test func `should keep the signing key in the Keychain when the Keychain accepts it`() {
        let secure = KeepingCredentials()
        let fallback = KeepingCredentials()
        let store = CredentialSigningKeyStore(secure: secure, fallback: fallback)

        store.save(Data([1, 2, 3]))

        #expect(store.load() == Data([1, 2, 3]))
        #expect(secure.values.count == 1)
        #expect(fallback.values.isEmpty)
        #expect(store.isSecure)
    }

    @Test func `should keep the signing key in the fallback store when the Keychain refuses it`() {
        let fallback = KeepingCredentials()
        let store = CredentialSigningKeyStore(secure: RefusingCredentials(), fallback: fallback)

        store.save(Data([1, 2, 3]))

        #expect(store.load() == Data([1, 2, 3]))
        #expect(fallback.values.count == 1)
        #expect(!store.isSecure)
    }

    @Test func `should forget the signing key from both stores when it is deleted`() {
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
