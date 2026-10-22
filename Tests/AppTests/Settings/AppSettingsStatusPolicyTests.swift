import Testing
import Foundation
import Domain
import Infrastructure
@testable import ClaudeBar

/// The warning switch picks the one status policy every surface reads.
@Suite @MainActor
struct AppSettingsStatusPolicyTests {
    @Test func `should follow the forecast once the person turns the warning on, and keep that choice`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        func load() -> AppSettings {
            AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        }
        let settings = load()
        #expect(settings.statusPolicy == .absolute)

        settings.burnRateWarningEnabled = true

        #expect(load().statusPolicy == .paceAware)
    }

    @Test func `should keep the person's warning choice when an old threshold is saved beside it`() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try Data(#"{"app":{"burnRateWarningEnabled":true,"burnRateThreshold":3.0}}"#.utf8).write(to: file)

        let settings = AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))

        #expect(settings.statusPolicy == .paceAware)
    }
}
