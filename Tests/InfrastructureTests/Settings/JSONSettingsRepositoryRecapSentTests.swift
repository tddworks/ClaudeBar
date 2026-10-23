import Foundation
import Testing
@testable import Infrastructure
import Domain

/// `alerts.recapSentAt`: when the last weekly recap went out, kept as seconds
/// since the reference date so a relaunch inside the week sends again never.
@Suite
struct JSONSettingsRepositoryRecapSentTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
    private var file: URL { directory.appendingPathComponent("settings.json") }

    private func repository() -> JSONSettingsRepository {
        JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
    }

    @Test func `should read no last send until a recap has gone out`() {
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(repository().lastSent() == nil)
    }

    @Test func `should remember when the last recap went out across restarts`() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let sentAt = Date(timeIntervalSince1970: 1_793_670_500)
        repository().setLastSent(sentAt)

        let relaunched = repository().lastSent()

        #expect(relaunched?.timeIntervalSince1970 == sentAt.timeIntervalSince1970)
    }
}
