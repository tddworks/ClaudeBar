import Testing
import Foundation
import Kit
@testable import ClaudeBar

@Suite @MainActor
struct AppSettingsStatusColorTests {
    private func makeSettings() -> (AppSettings, URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = dir.appendingPathComponent("settings.json")
        let settings = AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        return (settings, dir, file)
    }

    @Test
    func `should use the standard status colors when the person has set none`() {
        let (settings, dir, _) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(settings.statusColorPolicy == .default)
        #expect(!settings.statusColorPolicy.isActive)
    }

    @Test
    func `should remember the person's status color and high contrast after relaunch`() {
        let (settings, dir, file) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = RGBColorValue(hex: "#ABCDEF")!
        settings.setStatusColorOverride(custom, for: .warning)
        settings.highContrastEnabled = true

        let reloaded = AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        #expect(reloaded.statusColorOverrides[.warning] == custom)
        #expect(reloaded.statusColorOverrides[.healthy] == nil)
        #expect(reloaded.highContrastEnabled == true)
        #expect(reloaded.statusColorPolicy.color(for: .warning, appearance: .light) == custom)
        #expect(reloaded.statusColorPolicy.color(for: .healthy, appearance: .light)
                == StatusPalette.highContrastLight[.healthy])
    }

    @Test
    func `should drop the person's status colors but keep high contrast when they reset colors`() {
        let (settings, dir, _) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        settings.setStatusColorOverride(RGBColorValue(hex: "#112233"), for: .critical)
        settings.highContrastEnabled = true

        settings.resetStatusColors()

        #expect(settings.statusColorOverrides.isEmpty)
        #expect(settings.highContrastEnabled == true)
        #expect(settings.statusColorPolicy.isActive)
    }

    @Test
    func `should drop only the cleared status's color when the person clears one`() {
        let (settings, dir, _) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        settings.setStatusColorOverride(RGBColorValue(hex: "#111111"), for: .healthy)
        settings.setStatusColorOverride(RGBColorValue(hex: "#222222"), for: .depleted)

        settings.setStatusColorOverride(nil, for: .healthy)

        #expect(settings.statusColorOverrides[.healthy] == nil)
        #expect(settings.statusColorOverrides[.depleted]?.hexString == "#222222")
    }
}
