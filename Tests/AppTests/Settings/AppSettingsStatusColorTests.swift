import Testing
import Foundation
import Domain
import Infrastructure
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
    func `status color policy is default when nothing is set`() {
        let (settings, dir, _) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(settings.statusColorPolicy == .default)
        #expect(!settings.statusColorPolicy.isActive)
    }

    @Test
    func `overrides and high contrast persist to a reloaded instance`() {
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
    func `reset clears overrides but leaves high contrast alone`() {
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
    func `setting an override to nil removes only that status`() {
        let (settings, dir, _) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        settings.setStatusColorOverride(RGBColorValue(hex: "#111111"), for: .healthy)
        settings.setStatusColorOverride(RGBColorValue(hex: "#222222"), for: .depleted)

        settings.setStatusColorOverride(nil, for: .healthy)

        #expect(settings.statusColorOverrides[.healthy] == nil)
        #expect(settings.statusColorOverrides[.depleted]?.hexString == "#222222")
    }
}
