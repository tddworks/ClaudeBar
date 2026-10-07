import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for provider-level settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository Provider Settings Tests")
struct JSONSettingsRepositoryProviderTests {

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

    // MARK: - Provider Enabled State

    @Test
    func `should show a provider when the person never turned it off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isEnabled(forProvider: "claude") == true)
    }

    @Test
    func `should hide a provider that starts off when the person never turned it on`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.isEnabled(forProvider: "copilot", defaultValue: false) == false)
    }

    @Test
    func `should remember a provider turned off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        #expect(repo.isEnabled(forProvider: "claude") == false)
    }

    @Test
    func `should keep each provider on or off independently`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        repo.setEnabled(true, forProvider: "codex")

        #expect(repo.isEnabled(forProvider: "claude") == false)
        #expect(repo.isEnabled(forProvider: "codex") == true)
    }

    // MARK: - Custom Card URL

    @Test
    func `should open no custom page from a card until one is set`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `should remember a card's custom page`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == "https://claude.owo.nz/")
    }

    @Test
    func `should forget a card's custom page when it is cleared`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL(nil, forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `should forget a card's custom page when it is set to nothing`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL("", forProvider: "claude")
        #expect(repo.customCardURL(forProvider: "claude") == nil)
    }

    @Test
    func `should keep each provider's custom page apart`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCustomCardURL("https://claude.owo.nz/", forProvider: "claude")
        repo.setCustomCardURL("https://codex.example.com/", forProvider: "codex")

        #expect(repo.customCardURL(forProvider: "claude") == "https://claude.owo.nz/")
        #expect(repo.customCardURL(forProvider: "codex") == "https://codex.example.com/")
        #expect(repo.customCardURL(forProvider: "gemini") == nil)
    }

    // MARK: - Provider Order

    @Test
    func `should keep no provider order until the person arranges them`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.providerOrder() == [])
    }

    @Test
    func `should remember the provider order across restarts`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setProviderOrder(["gemini", "claude", "codex"])

        // Read back through a fresh repository over the same file, so the
        // value really hit settings.json and not just memory.
        let store = JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        let reloaded = JSONSettingsRepository(store: store)
        #expect(reloaded.providerOrder() == ["gemini", "claude", "codex"])
    }

    @Test
    func `should forget the provider order when it is cleared`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setProviderOrder(["gemini", "claude", "codex"])
        repo.setProviderOrder([])
        #expect(repo.providerOrder() == [])
    }

    @Test
    func `should remember an order that names only some providers`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setProviderOrder(["codex"])
        #expect(repo.providerOrder() == ["codex"])
    }

    // MARK: - Hidden Quota Keys (issue #140)

    @Test
    func `should hide no quotas until the person hides some (#140)`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.hiddenQuotaKeys(forProvider: "gemini") == [])
    }

    @Test
    func `should remember hidden quotas across restarts (#140)`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHiddenQuotaKeys(["model:gemini-2.0-flash", "time:mcp"], forProvider: "gemini")

        // Reopen the same settings file as a fresh repository
        let store = JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        let reopened = JSONSettingsRepository(store: store)

        #expect(reopened.hiddenQuotaKeys(forProvider: "gemini") == ["model:gemini-2.0-flash", "time:mcp"])
    }

    @Test
    func `should keep each provider's hidden quotas apart (#140)`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHiddenQuotaKeys(["model:gemini-2.0-flash"], forProvider: "gemini")
        repo.setHiddenQuotaKeys(["weekly"], forProvider: "codex")

        #expect(repo.hiddenQuotaKeys(forProvider: "gemini") == ["model:gemini-2.0-flash"])
        #expect(repo.hiddenQuotaKeys(forProvider: "codex") == ["weekly"])
        #expect(repo.hiddenQuotaKeys(forProvider: "claude") == [])
    }

    @Test
    func `should show every quota again once nothing is hidden (#140)`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setHiddenQuotaKeys(["model:gemini-2.0-flash"], forProvider: "gemini")
        repo.setHiddenQuotaKeys([], forProvider: "gemini")

        #expect(repo.hiddenQuotaKeys(forProvider: "gemini") == [])
    }

    // MARK: - Claude Settings

    @Test
    func `should read Claude through its CLI when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeProbeMode() == .cli)
    }

    @Test
    func `should remember reading Claude through the API`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeProbeMode(.api)
        #expect(repo.claudeProbeMode() == .api)
    }

    @Test
    func `should fall back to Claude's CLI when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.claudeCliFallbackEnabled() == true)
    }

    @Test
    func `should remember turning Claude's CLI fallback off`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setClaudeCliFallbackEnabled(false)
        #expect(repo.claudeCliFallbackEnabled() == false)
    }

    // MARK: - Codex Settings

    @Test
    func `should read Codex over RPC when the person never chose`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.codexProbeMode() == .rpc)
    }

    @Test
    func `should remember reading Codex through the API`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCodexProbeMode(.api)
        #expect(repo.codexProbeMode() == .api)
    }

    @Test
    func `should not count Codex as verified before it ever answered`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.codexVerifiedAtLeastOnce() == false)
    }

    @Test
    func `should remember whether Codex has been verified`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setCodexVerifiedAtLeastOnce(true)
        #expect(repo.codexVerifiedAtLeastOnce() == true)

        repo.setCodexVerifiedAtLeastOnce(false)
        #expect(repo.codexVerifiedAtLeastOnce() == false)
    }

    // Hook settings are Kotlin's: activity/FileHookSettingsTest.
}
