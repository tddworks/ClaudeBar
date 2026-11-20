import Testing
import Foundation
@testable import ClaudeBar
import Storage

@Suite @MainActor
struct AppSettingsNativeIconsTests {
    @Test func `should remember native menu bar icons, off by default, without changing status colors`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        func load() -> AppSettings {
            AppSettings(repository: AppSettingsFile(store: JSONSettingsStore(fileURL: file)), settings: Storage.makeSettings(fileURL: file))
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
