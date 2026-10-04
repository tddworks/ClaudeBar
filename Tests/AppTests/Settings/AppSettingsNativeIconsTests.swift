import Testing
import Foundation
import Domain
import Infrastructure
@testable import ClaudeBar

@Suite @MainActor
struct AppSettingsNativeIconsTests {
    @Test func `native icons are opt in and persist independently of status colors`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        func load() -> AppSettings {
            AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        }
        let settings = load()
        #expect(!settings.nativeMenuBarIconsEnabled)
        settings.nativeMenuBarIconsEnabled = true
        #expect(load().nativeMenuBarIconsEnabled)
        #expect(load().statusColorPolicy == .default)
        settings.nativeMenuBarIconsEnabled = false
        #expect(!load().nativeMenuBarIconsEnabled)
    }
}
