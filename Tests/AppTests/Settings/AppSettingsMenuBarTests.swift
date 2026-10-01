import Testing
import Foundation
import Domain
import Infrastructure
@testable import ClaudeBar

@Suite @MainActor
struct AppSettingsMenuBarTests {
    @Test
    func `each provider keeps its quota settings when removed promoted and reloaded`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        repo.setMenuBarPercentageQuotaKey("session")
        repo.setMenuBarSecondaryQuotaKey("weekly")
        repo.setMenuBarStackedEnabled(true)
        let settings = AppSettings(repository: repo)
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
        let reloaded = AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)))
        #expect(reloaded.menuBarProviderIds == ["grok", "claude", "codex"])
        #expect(reloaded.menuBarConfiguration(for: "claude") == claude)
        #expect(reloaded.menuBarConfiguration(for: "grok") == grok)
    }

    @Test
    func `observable menu bar selection normalizes without recursive setters`() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json")))
        let settings = AppSettings(repository: repo)
        settings.menuBarAdditionalProviderIds = ["claude", "codex", "gemini", "copilot"]
        #expect(settings.menuBarAdditionalProviderIds == ["codex", "gemini"])
        settings.menuBarPercentageProviderId = "codex"
        #expect(settings.menuBarAdditionalProviderIds == ["gemini"])
        settings.menuBarAdditionalProviderIds = []
        #expect(repo.menuBarAdditionalProviderIds().isEmpty)
    }
}
