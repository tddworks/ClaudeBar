import Testing
import Foundation
import Quotas
import DataSources
import Providers
import Monitoring
import Leaderboard
import Activity
import Alerting
import LocalAPI
@testable import Storage

/// Tests for multi-account provider settings in JSONSettingsRepository.
@Suite("JSONSettingsRepository Multi-Account Tests")
struct JSONSettingsRepositoryMultiAccountTests {

    private func makeRepository() -> (JSONSettingsRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)
        let repo = JSONSettingsRepository(store: store)
        return (repo, tempDir)
    }

    private func makeStore() -> (JSONSettingsStore, JSONSettingsRepository, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)
        return (store, JSONSettingsRepository(store: store), tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func account(
        _ accountId: String,
        label: String? = nil,
        email: String? = nil,
        organization: String? = nil,
        probeConfig: [String: String] = [:]
    ) -> ProviderAccountConfig {
        ProviderAccountConfig(
            accountId: accountId,
            label: label ?? accountId.capitalized,
            email: email,
            organization: organization,
            probeConfig: probeConfig
        )
    }

    // MARK: - Backward Compatibility

    @Test
    func `should have no added logins for a provider never set up`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.accounts(forProvider: "claude").isEmpty)
    }

    @Test
    func `should keep a provider's other settings when a login is added`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        repo.addAccount(account("personal"), forProvider: "claude")

        #expect(repo.isEnabled(forProvider: "claude") == false)
    }

    // MARK: - Adding

    @Test
    func `should remember an added login and its name`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.accountId == "personal")
        #expect(accounts.first?.label == "Personal")
    }

    @Test
    func `should keep added logins in the order they were added`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal", "work"])
    }

    @Test
    func `should remember everything about an added login`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        let original = account(
            "work",
            label: "Work - Acme",
            email: "dev@acme.example",
            organization: "Acme",
            probeConfig: ["profile": "acme", "tokenEnvVar": "ACME_TOKEN"]
        )
        repo.addAccount(original, forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").first == original)
    }

    @Test
    func `should replace a login added again rather than list it twice`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Old"), forProvider: "claude")
        repo.addAccount(account("personal", label: "New"), forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "New")
    }

    @Test
    func `should keep each provider's added logins apart`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "codex")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
        #expect(repo.accounts(forProvider: "codex").map(\.accountId) == ["work"])
    }

    // MARK: - Updating

    @Test
    func `should change a login in place, keeping its position`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")
        repo.addAccount(account("work", label: "Work"), forProvider: "claude")

        repo.updateAccount(account("personal", label: "Home"), forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.map(\.accountId) == ["personal", "work"])
        #expect(accounts.first?.label == "Home")
    }

    @Test
    func `should leave the logins as they are when changing one that does not exist`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.updateAccount(account("ghost", label: "Ghost"), forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
    }

    // MARK: - Removing

    @Test
    func `should remove only the named login`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "claude")

        repo.removeAccount(accountId: "personal", forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["work"])
    }

    @Test
    func `should leave the logins as they are when removing one that does not exist`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.removeAccount(accountId: "ghost", forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
    }

    @Test
    func `should leave the provider with only its default login once the last added one is removed`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.removeAccount(accountId: "personal", forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").isEmpty)
    }

    // MARK: - The default login's name

    @Test
    func `should remember the default login's name per provider, and forget it when cleared`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setDefaultAccountLabel("Personal", forProvider: "claude")
        #expect(repo.defaultAccountLabel(forProvider: "claude") == "Personal")
        #expect(repo.defaultAccountLabel(forProvider: "codex") == nil)

        repo.setDefaultAccountLabel(nil, forProvider: "claude")
        #expect(repo.defaultAccountLabel(forProvider: "claude") == nil)
    }

    // MARK: - Key Pattern (JSONSettingsStore)

    @Test
    func `should keep the default login's name under its provider in settings.json`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        repo.setDefaultAccountLabel("Personal", forProvider: "claude")

        #expect(store.read(key: "providers.claude.defaultAccountLabel") == "Personal")
    }

    @Test
    func `should keep added logins under their provider in settings.json`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")

        let raw: [Any]? = store.read(key: "providers.claude.accounts")
        #expect(raw?.count == 1)
        #expect((raw?.first as? [String: Any])?["accountId"] as? String == "personal")
    }

    @Test
    func `should have no added logins when settings.json lists none`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        store.write(value: [Any](), key: "providers.claude.accounts")

        #expect(repo.accounts(forProvider: "claude").isEmpty)
    }

    @Test
    func `should skip a broken login in settings.json and keep the rest`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        store.write(
            value: [["not": "an account"], ["accountId": "personal", "label": "Personal", "probeConfig": [:]]],
            key: "providers.claude.accounts"
        )

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
    }

    // MARK: - Persistence Across Instances

    @Test
    func `should remember added logins and the default login's name across restarts`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")
        repo.setDefaultAccountLabel("Me", forProvider: "claude")

        let reopened = JSONSettingsRepository(store: JSONSettingsStore(fileURL: store.fileURL))

        #expect(reopened.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
        #expect(reopened.defaultAccountLabel(forProvider: "claude") == "Me")
    }
}
