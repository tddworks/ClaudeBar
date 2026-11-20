import Testing
import Foundation
@testable import ClaudeBar
import Domain
import Storage

@Suite @MainActor
struct AppSettingsMenuBarTests {
    @Test
    func `should remember whether account labels show in the menu bar, on by default`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let settings = AppSettings(repository: AppSettingsFile(store: JSONSettingsStore(fileURL: file)), settings: Storage.makeSettings(fileURL: file))
        #expect(settings.menuBarAccountLabelsEnabled)
        settings.menuBarAccountLabelsEnabled = false
        let reloaded = AppSettings(repository: AppSettingsFile(store: JSONSettingsStore(fileURL: file)), settings: Storage.makeSettings(fileURL: file))
        #expect(!reloaded.menuBarAccountLabelsEnabled)
        reloaded.menuBarAccountLabelsEnabled = true
        let enabled = AppSettings(repository: AppSettingsFile(store: JSONSettingsStore(fileURL: file)), settings: Storage.makeSettings(fileURL: file))
        #expect(enabled.menuBarAccountLabelsEnabled)
    }

    @Test
    func `should keep each menu bar provider's quota choices when it is removed, promoted or the app relaunches`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let repo = AppSettingsFile(store: JSONSettingsStore(fileURL: file))
        repo.setMenuBarPercentageQuotaKey("session")
        repo.setMenuBarSecondaryQuotaKey("weekly")
        repo.setMenuBarStackedEnabled(true)
        let settings = AppSettings(repository: repo, settings: Storage.makeSettings(fileURL: file))
        let claude = settings.menuBarConfiguration(for: "claude")
        let grok = MenuBarProviderSettings(primaryQuotaKey: "weekly", secondaryQuotaKey: "chat", stacked: true, stackedSize: "large")
        settings.setMenuBarProviderIds(["claude", "grok", "codex", "gemini"])
        #expect(settings.menuBarProviderIds == ["claude", "grok", "codex"])
        settings.setMenuBarConfiguration(grok, for: "grok")
        #expect(settings.menuBarConfiguration(for: "claude") == claude)
        settings.setMenuBarProviderIds(["grok", "codex"])
        #expect(settings.menuBarConfiguration(for: "grok") == grok)
        #expect(settings.menuBarPercentageQuotaKey == "weekly")
        settings.setMenuBarProviderIds(["grok", "claude", "codex"])
        let reloaded = AppSettings(repository: AppSettingsFile(store: JSONSettingsStore(fileURL: file)), settings: Storage.makeSettings(fileURL: file))
        #expect(reloaded.menuBarProviderIds == ["grok", "claude", "codex"])
        #expect(reloaded.menuBarConfiguration(for: "claude") == claude)
        #expect(reloaded.menuBarConfiguration(for: "grok") == grok)
    }

    @Test
    func `should keep the primary provider out of the other menu bar providers and at most two of them`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = AppSettingsFile(store: JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json")))
        let settings = AppSettings(repository: repo, settings: Storage.makeSettings(fileURL: dir.appendingPathComponent("settings.json")))
        settings.menuBarAdditionalProviderIds = ["claude", "codex", "gemini", "copilot"]
        #expect(settings.menuBarAdditionalProviderIds == ["codex", "gemini"])
        settings.menuBarPercentageProviderId = "codex"
        #expect(settings.menuBarAdditionalProviderIds == ["gemini"])
        settings.menuBarAdditionalProviderIds = []
        #expect(repo.menuBarAdditionalProviderIds().isEmpty)
    }
}
