import Testing
import Foundation
import Domain
import Infrastructure
@testable import ClaudeBar

/// Tests for the observable alert-threshold settings (issue #68):
/// add/remove through AppSettings must persist to settings.json.
@Suite @MainActor
struct AppSettingsAlertThresholdTests {

    @Test
    func `alert thresholds default to empty`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json")))

        let settings = AppSettings(repository: repo)

        #expect(settings.alertThresholds.isEmpty)
    }

    @Test
    func `adding a threshold persists through the repository`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        let settings = AppSettings(repository: repo)

        settings.alertThresholds = [60, 35]

        #expect(repo.alertThresholds().map(\.percent) == [60, 35])
    }

    @Test
    func `removing a threshold persists the shorter list`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        let settings = AppSettings(repository: repo)
        settings.alertThresholds = [60, 35]

        settings.alertThresholds = [60]

        #expect(repo.alertThresholds().map(\.percent) == [60])
    }

    @Test
    func `alert thresholds survive an app settings reload`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        let settings = AppSettings(repository: repo)
        settings.alertThresholds = [60, 35]

        let reloaded = AppSettings(repository: JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: file)
        ))

        #expect(reloaded.alertThresholds == [60, 35])
    }
}
