import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for app-level settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository App Settings Tests")
struct JSONSettingsRepositoryAppTests {

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
    func `additional menu bar providers preserve legacy selection and survive reload`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        repo.setMenuBarPercentageProviderId("codex")
        #expect(repo.menuBarAdditionalProviderIds().isEmpty)
        repo.setMenuBarAdditionalProviderIds(["claude", "gemini"])
        let reloaded = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: dir.appendingPathComponent("settings.json")
        ))
        #expect(reloaded.menuBarPercentageProviderId() == "codex")
        #expect(reloaded.menuBarAdditionalProviderIds() == ["claude", "gemini"])
    }

    @Test
    func `menu bar providers remove duplicates and cap the total at three`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        repo.setMenuBarAdditionalProviderIds(["claude", "codex", "codex", "", "gemini", "copilot"])
        #expect(repo.menuBarAdditionalProviderIds() == ["codex", "gemini"])
        repo.setMenuBarPercentageProviderId("codex")
        #expect(repo.menuBarAdditionalProviderIds() == ["gemini"])
    }

    // MARK: - Theme

    @Test
    func `themeMode defaults to system`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.themeMode() == "system")
    }

    @Test
    func `setThemeMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setThemeMode("dark")
        #expect(repo.themeMode() == "dark")
    }

    @Test
    func `userHasChosenTheme defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.userHasChosenTheme() == false)
    }

    @Test
    func `setUserHasChosenTheme persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setUserHasChosenTheme(true)
        #expect(repo.userHasChosenTheme() == true)
    }

    // MARK: - Display

    @Test
    func `usageDisplayMode defaults to remaining`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.usageDisplayMode() == "remaining")
    }

    @Test
    func `setUsageDisplayMode persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setUsageDisplayMode("used")
        #expect(repo.usageDisplayMode() == "used")
    }

    @Test
    func `menuBarPercentageEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarPercentageEnabled() == false)
    }

    @Test
    func `menuBarPercentageSelection defaults to claude session`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarPercentageProviderId() == "claude")
        #expect(repo.menuBarPercentageQuotaKey() == "session")
    }

    @Test
    func `setMenuBarPercentageSettings persists values`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setMenuBarPercentageEnabled(true)
        repo.setMenuBarPercentageProviderId("codex")
        repo.setMenuBarPercentageQuotaKey("weekly")

        #expect(repo.menuBarPercentageEnabled() == true)
        #expect(repo.menuBarPercentageProviderId() == "codex")
        #expect(repo.menuBarPercentageQuotaKey() == "weekly")
    }

    @Test
    func `menuBarSecondaryQuotaKey defaults to empty`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarSecondaryQuotaKey() == "")
    }

    @Test
    func `setMenuBarSecondaryQuotaKey persists value`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setMenuBarSecondaryQuotaKey("weekly")

        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.menuBarSecondaryQuotaKey() == "weekly")
    }

    @Test
    func `menuBarDurationEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarDurationEnabled() == false)
    }

    @Test
    func `setMenuBarDurationEnabled persists value`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setMenuBarDurationEnabled(true)

        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.menuBarDurationEnabled() == true)
    }

    @Test
    func `menuBarStackedEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarStackedEnabled() == false)
    }

    @Test
    func `setMenuBarStackedEnabled persists value`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setMenuBarStackedEnabled(true)

        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.menuBarStackedEnabled() == true)
    }

    @Test
    func `menuBarStackedSize defaults to small`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarStackedSize() == "small")
    }

    @Test
    func `setMenuBarStackedSize persists value`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setMenuBarStackedSize("large")

        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.menuBarStackedSize() == "large")
    }

    @Test
    func `showDailyUsageCards defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.showDailyUsageCards() == true)
    }

    @Test
    func `setShowDailyUsageCards persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setShowDailyUsageCards(false)
        #expect(repo.showDailyUsageCards() == false)
    }

    // MARK: - Touch Bar

    @Test
    func `touchBarEnabled defaults to true`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.touchBarEnabled() == true)
    }

    @Test
    func `setTouchBarEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setTouchBarEnabled(false)
        #expect(repo.touchBarEnabled() == false)
    }

    // MARK: - Overview

    @Test
    func `overviewModeEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.overviewModeEnabled() == false)
    }

    @Test
    func `setOverviewModeEnabled persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setOverviewModeEnabled(true)
        #expect(repo.overviewModeEnabled() == true)
    }

    // MARK: - Background Sync

    @Test
    func `backgroundSyncEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.backgroundSyncEnabled() == false)
    }

    @Test
    func `backgroundSyncInterval defaults to 600`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        // Power-conscious 10-minute default for background refresh (issue #204).
        #expect(repo.backgroundSyncInterval() == 600)
    }

    @Test
    func `setBackgroundSyncInterval persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setBackgroundSyncInterval(120)
        #expect(repo.backgroundSyncInterval() == 120)
    }

    // MARK: - Claude API Budget

    @Test
    func `claudeApiBudgetEnabled defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeApiBudgetEnabled() == false)
    }

    @Test
    func `claudeApiBudget defaults to 0`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeApiBudget() == 0)
    }

    @Test
    func `setClaudeApiBudget persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeApiBudget(50.0)
        #expect(repo.claudeApiBudget() == 50.0)
    }

    // MARK: - Updates

    @Test
    func `receiveBetaUpdates defaults to false`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.receiveBetaUpdates() == false)
    }

    @Test
    func `setReceiveBetaUpdates persists value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setReceiveBetaUpdates(true)
        #expect(repo.receiveBetaUpdates() == true)
    }

    // MARK: - Persistence across instances

    @Test
    func `values persist across separate repository instances`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setThemeMode("cli")
        repo1.setShowDailyUsageCards(false)
        repo1.setTouchBarEnabled(false)
        repo1.setOverviewModeEnabled(true)
        repo1.setMenuBarPercentageEnabled(true)
        repo1.setMenuBarPercentageProviderId("codex")
        repo1.setMenuBarPercentageQuotaKey("model:gpt-5")

        // New repo, same store
        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.themeMode() == "cli")
        #expect(repo2.showDailyUsageCards() == false)
        #expect(repo2.touchBarEnabled() == false)
        #expect(repo2.overviewModeEnabled() == true)
        #expect(repo2.menuBarPercentageEnabled() == true)
        #expect(repo2.menuBarPercentageProviderId() == "codex")
        #expect(repo2.menuBarPercentageQuotaKey() == "model:gpt-5")
    }

    // MARK: - Status Colors

    @Test
    func `status colors default to no overrides and high contrast off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        #expect(repo.statusColorOverrides().isEmpty)
        #expect(repo.highContrastEnabled() == false)
    }

    @Test
    func `status color overrides and high contrast survive reload`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        var overrides = StatusColorOverrides.none
        overrides[.critical] = RGBColorValue(hex: "#B81F1F")
        overrides[.healthy] = RGBColorValue(hex: "#17703A")
        repo.setStatusColorOverrides(overrides)
        repo.setHighContrastEnabled(true)

        let reloaded = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: dir.appendingPathComponent("settings.json")))
        #expect(reloaded.statusColorOverrides() == overrides)
        #expect(reloaded.statusColorOverrides()[.warning] == nil)
        #expect(reloaded.statusColorOverrides()[.depleted] == nil)
        #expect(reloaded.highContrastEnabled() == true)
    }

    @Test
    func `clearing all status color overrides removes the key`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        var overrides = StatusColorOverrides.none
        overrides[.warning] = RGBColorValue(hex: "#8A5A00")
        repo.setStatusColorOverrides(overrides)
        repo.setStatusColorOverrides(.none)

        let reloaded = JSONSettingsRepository(store: JSONSettingsStore(
            fileURL: dir.appendingPathComponent("settings.json")))
        #expect(reloaded.statusColorOverrides().isEmpty)
        let raw = try? String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(raw?.contains("statusColorOverrides") == false)
    }
}
