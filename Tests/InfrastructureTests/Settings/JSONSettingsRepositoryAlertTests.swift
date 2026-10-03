import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for alert threshold persistence in JSONSettingsRepository (issue #68).
@Suite("JSONSettingsRepository Alert Threshold Tests")
struct JSONSettingsRepositoryAlertTests {

    private func makeRepository() -> (JSONSettingsRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)
        let repo = JSONSettingsRepository(store: store)
        return (repo, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test
    func `alert thresholds default to empty`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.alertThresholds().isEmpty)
    }

    @Test
    func `setAlertThresholds persists and reads back`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setAlertThresholds([QuotaAlertThreshold(percent: 60), QuotaAlertThreshold(percent: 35)])

        #expect(repo.alertThresholds() == [QuotaAlertThreshold(percent: 60), QuotaAlertThreshold(percent: 35)])
    }

    @Test
    func `alert thresholds survive a repository reload`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setAlertThresholds([QuotaAlertThreshold(percent: 35)])

        let reloaded = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: dir.appendingPathComponent("settings.json")
        ))
        #expect(reloaded.alertThresholds() == [QuotaAlertThreshold(percent: 35)])
    }

    @Test
    func `setting an empty threshold list clears stored thresholds`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setAlertThresholds([QuotaAlertThreshold(percent: 35)])
        repo.setAlertThresholds([])

        #expect(repo.alertThresholds().isEmpty)
    }

    @Test
    func `thresholds are clamped into 0 to 100 on the way through`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setAlertThresholds([QuotaAlertThreshold(percent: 120), QuotaAlertThreshold(percent: -5)])

        #expect(repo.alertThresholds().map(\.percent) == [100, 0])
    }
}
