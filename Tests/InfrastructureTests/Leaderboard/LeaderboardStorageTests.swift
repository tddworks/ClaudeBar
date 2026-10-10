import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

/// The membership's record in `settings.json`. The private key isn't here:
/// the `Leaderboard` module keeps it (`FallbackSigningKeyStoreTests`).
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

    @Test func `should remember which added devices were shown after a relaunch, and forget them with the membership`() throws {
        let (settings, url) = repository()
        settings.saveLeaderboardRecord(LeaderboardRecord(username: "tokenwhale", sharing: ["claude"], visible: true,
                                                         lastUpload: nil, shownDevices: ["k3", "k2"]))

        let relaunched = JSONSettingsRepository(store: JSONSettingsStore(fileURL: url), credentials: UserDefaults(suiteName: UUID().uuidString)!,
                                                secureCredentials: KeepingCredentials())
        #expect(relaunched.leaderboardRecord()?.shownDevices == ["k2", "k3"])

        relaunched.saveLeaderboardRecord(nil)
        #expect(try !String(contentsOf: url, encoding: .utf8).contains("k2"))
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
}
