import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for app-level settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository App Settings Tests")
struct JSONSettingsRepositoryAppTests {

    @Test
    func `should show account labels in the menu bar when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        repo.setMenuBarPercentageEnabled(true)
        #expect(repo.menuBarAccountLabelsEnabled())
    }

    @Test
    func `should remember account labels turned off and back on across restarts`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        let fileURL = dir.appendingPathComponent("settings.json")
        repo.setMenuBarAccountLabelsEnabled(false)
        let disabled = JSONSettingsRepository(store: JSONSettingsStore(fileURL: fileURL))
        #expect(!disabled.menuBarAccountLabelsEnabled())
        disabled.setMenuBarAccountLabelsEnabled(true)
        let enabled = JSONSettingsRepository(store: JSONSettingsStore(fileURL: fileURL))
        #expect(enabled.menuBarAccountLabelsEnabled())
    }

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
    func `should keep the chosen menu bar provider and remember the extra ones across restarts`() {
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
    func `should show at most three distinct providers in the menu bar, never repeating the main one`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        repo.setMenuBarAdditionalProviderIds(["claude", "codex", "codex", "", "gemini", "copilot"])
        #expect(repo.menuBarAdditionalProviderIds() == ["codex", "gemini"])
        repo.setMenuBarPercentageProviderId("codex")
        #expect(repo.menuBarAdditionalProviderIds() == ["gemini"])
    }

    // MARK: - Theme

    @Test
    func `should follow the system theme when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.themeMode() == "system")
    }

    @Test
    func `should remember the chosen theme`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setThemeMode("dark")
        #expect(repo.themeMode() == "dark")
    }

    @Test
    func `should print a theme's own text everywhere until the person picks another style`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.themeTextStyle() == "themed")
    }

    @Test
    func `should remember the chosen text style`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setThemeTextStyle("classic")
        #expect(repo.themeTextStyle() == "classic")
    }

    @Test
    func `should put a theme's runner on its floor until the person turns it off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.themeRunnerShown())
    }

    @Test
    func `should remember that the runner is turned off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setThemeRunnerShown(false)
        #expect(!repo.themeRunnerShown())
    }

    @Test
    func `should know the person has not chosen a theme yet`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.userHasChosenTheme() == false)
    }

    @Test
    func `should remember that the person chose a theme`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setUserHasChosenTheme(true)
        #expect(repo.userHasChosenTheme() == true)
    }

    // MARK: - Display

    @Test
    func `should show what is left when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.usageDisplayMode() == "remaining")
    }

    @Test
    func `should remember showing what is used`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setUsageDisplayMode("used")
        #expect(repo.usageDisplayMode() == "used")
    }

    @Test
    func `should not show a percentage in the menu bar until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarPercentageEnabled() == false)
    }

    @Test
    func `should pick Claude's session for the menu bar percentage when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarPercentageProviderId() == "claude")
        #expect(repo.menuBarPercentageQuotaKey() == "session")
    }

    @Test
    func `should remember the menu bar percentage, its provider and its quota`() {
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
    func `should show no second quota in the menu bar until one is chosen`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarSecondaryQuotaKey() == "")
    }

    @Test
    func `should remember the second menu bar quota across restarts`() {
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
    func `should not show the time to reset in the menu bar until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarDurationEnabled() == false)
    }

    @Test
    func `should remember showing the time to reset in the menu bar across restarts`() {
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
    func `should not stack the menu bar readouts until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarStackedEnabled() == false)
    }

    @Test
    func `should remember stacked menu bar readouts across restarts`() {
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
    func `should stack the menu bar readouts small when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarStackedSize() == "small")
    }

    @Test
    func `should remember the stacked readout size across restarts`() {
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
    func `should show the daily usage cards when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.showDailyUsageCards() == true)
    }

    @Test
    func `should show a single readout's logo only once asked, and keep showing it`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.menuBarProviderLogoEnabled() == false)
        repo.setMenuBarProviderLogoEnabled(true)
        #expect(repo.menuBarProviderLogoEnabled() == true)
    }

    @Test
    func `should show account emails until hidden, and keep them hidden`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.hideAccountEmail() == false)
        repo.setHideAccountEmail(true)
        #expect(repo.hideAccountEmail() == true)
    }

    @Test
    func `should show the person's globe country until hidden, and keep it hidden`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.hideLeaderboardCountry() == false)
        repo.setHideLeaderboardCountry(true)
        #expect(repo.hideLeaderboardCountry() == true)
    }

    @Test
    func `should show the person's leaderboard name until hidden, and keep it hidden`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.hideLeaderboardName() == false)
        repo.setHideLeaderboardName(true)
        #expect(repo.hideLeaderboardName() == true)
    }

    @Test
    func `should remember hiding the daily usage cards`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setShowDailyUsageCards(false)
        #expect(repo.showDailyUsageCards() == false)
    }

    // MARK: - Popover Text Size

    @Test
    func `popoverTextSize defaults to medium`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.popoverTextSize() == "medium")
    }

    @Test
    func `setPopoverTextSize persists across reloads`() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: fileURL)
        let repo1 = JSONSettingsRepository(store: store)
        repo1.setPopoverTextSize("extraLarge")

        let repo2 = JSONSettingsRepository(store: store)
        #expect(repo2.popoverTextSize() == "extraLarge")
    }

    // MARK: - Touch Bar

    @Test
    func `should show quotas on the Touch Bar when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.touchBarEnabled() == true)
    }

    @Test
    func `should remember turning the Touch Bar off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setTouchBarEnabled(false)
        #expect(repo.touchBarEnabled() == false)
    }

    // MARK: - Overview

    @Test
    func `should not start in the overview until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.overviewModeEnabled() == false)
    }

    @Test
    func `should remember turning the overview on`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setOverviewModeEnabled(true)
        #expect(repo.overviewModeEnabled() == true)
    }

    // MARK: - Background Sync

    @Test
    func `should not refresh in the background until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.backgroundSyncEnabled() == false)
    }

    @Test
    func `should refresh in the background every ten minutes when the person never chose (#204)`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        // Power-conscious 10-minute default for background refresh (issue #204).
        #expect(repo.backgroundSyncInterval() == 600)
    }

    @Test
    func `should remember the chosen background refresh interval`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setBackgroundSyncInterval(120)
        #expect(repo.backgroundSyncInterval() == 120)
    }

    // MARK: - Claude API Budget

    @Test
    func `should not track a Claude API budget until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeApiBudgetEnabled() == false)
    }

    @Test
    func `should start with no Claude API budget`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeApiBudget() == 0)
    }

    @Test
    func `should remember the Claude API budget`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeApiBudget(50.0)
        #expect(repo.claudeApiBudget() == 50.0)
    }

    // MARK: - Updates

    @Test
    func `should not offer beta updates until asked`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.receiveBetaUpdates() == false)
    }

    @Test
    func `should remember choosing beta updates`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setReceiveBetaUpdates(true)
        #expect(repo.receiveBetaUpdates() == true)
    }

    // MARK: - Persistence across instances

    @Test
    func `should keep every app choice across restarts`() {
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
    func `should use the theme's status colours without high contrast when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }
        #expect(repo.statusColorOverrides().isEmpty)
        #expect(repo.highContrastEnabled() == false)
    }

    @Test
    func `should remember custom status colours and high contrast across restarts`() {
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
    func `should leave no trace of custom status colours once they are all cleared`() {
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
