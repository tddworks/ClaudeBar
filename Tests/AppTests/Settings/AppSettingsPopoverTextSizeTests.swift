import Testing
import Foundation
import Domain
import Infrastructure
@testable import ClaudeBar

@Suite @MainActor
struct AppSettingsPopoverTextSizeTests {
    @Test func `popover text size defaults to Default and survives a reload`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        func load() -> AppSettings {
            AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        }

        let settings = load()
        #expect(settings.popoverTextSize == .default)
        #expect(settings.popoverTextSize == .medium)

        settings.popoverTextSize = .extraLarge
        #expect(load().popoverTextSize == .extraLarge)

        settings.popoverTextSize = .large
        #expect(load().popoverTextSize == .large)
    }

    @Test func `an unknown stored size renders Default instead of failing`() {
        // A settings file written by a newer build must not leave this build
        // with a size it cannot draw.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
            .setPopoverTextSize("gigantic")

        let settings = AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        #expect(settings.popoverTextSize == .medium)
    }
}
