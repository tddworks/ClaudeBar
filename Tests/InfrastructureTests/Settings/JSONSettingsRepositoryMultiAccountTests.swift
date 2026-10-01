import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

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
    func `accounts is empty for a provider that was never configured`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.accounts(forProvider: "claude").isEmpty)
    }

    @Test
    func `activeAccountId is nil for a provider that was never configured`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        #expect(repo.activeAccountId(forProvider: "claude") == nil)
    }

    @Test
    func `existing single-account settings survive account writes`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setEnabled(false, forProvider: "claude")
        repo.addAccount(account("personal"), forProvider: "claude")

        #expect(repo.isEnabled(forProvider: "claude") == false)
    }

    // MARK: - Adding

    @Test
    func `addAccount persists the account`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.accountId == "personal")
        #expect(accounts.first?.label == "Personal")
    }

    @Test
    func `addAccount preserves insertion order`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal", "work"])
    }

    @Test
    func `addAccount round-trips every field`() {
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
    func `addAccount with an existing id replaces rather than duplicates`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Old"), forProvider: "claude")
        repo.addAccount(account("personal", label: "New"), forProvider: "claude")

        let accounts = repo.accounts(forProvider: "claude")
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "New")
    }

    @Test
    func `accounts are namespaced per provider`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "codex")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
        #expect(repo.accounts(forProvider: "codex").map(\.accountId) == ["work"])
    }

    // MARK: - Updating

    @Test
    func `updateAccount replaces the matching account in place`() {
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
    func `updateAccount for an unknown id leaves accounts unchanged`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.updateAccount(account("ghost", label: "Ghost"), forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
    }

    // MARK: - Removing

    @Test
    func `removeAccount deletes only the named account`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "claude")

        repo.removeAccount(accountId: "personal", forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["work"])
    }

    @Test
    func `removeAccount for an unknown id leaves accounts unchanged`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.removeAccount(accountId: "ghost", forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
    }

    @Test
    func `removing the last account returns the provider to single-account state`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.removeAccount(accountId: "personal", forProvider: "claude")

        #expect(repo.accounts(forProvider: "claude").isEmpty)
    }

    @Test
    func `removing the active account clears the active pointer`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "claude")
        repo.setActiveAccountId("personal", forProvider: "claude")

        repo.removeAccount(accountId: "personal", forProvider: "claude")

        #expect(repo.activeAccountId(forProvider: "claude") == nil)
    }

    @Test
    func `removing a non-active account keeps the active pointer`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.addAccount(account("personal"), forProvider: "claude")
        repo.addAccount(account("work"), forProvider: "claude")
        repo.setActiveAccountId("work", forProvider: "claude")

        repo.removeAccount(accountId: "personal", forProvider: "claude")

        #expect(repo.activeAccountId(forProvider: "claude") == "work")
    }

    // MARK: - Active Account

    @Test
    func `setActiveAccountId persists the value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setActiveAccountId("work", forProvider: "claude")

        #expect(repo.activeAccountId(forProvider: "claude") == "work")
    }

    @Test
    func `setActiveAccountId to nil clears the value`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setActiveAccountId("work", forProvider: "claude")
        repo.setActiveAccountId(nil, forProvider: "claude")

        #expect(repo.activeAccountId(forProvider: "claude") == nil)
    }

    @Test
    func `active account is namespaced per provider`() {
        let (repo, dir) = makeRepository()
        defer { cleanup(dir) }

        repo.setActiveAccountId("personal", forProvider: "claude")
        repo.setActiveAccountId("work", forProvider: "codex")

        #expect(repo.activeAccountId(forProvider: "claude") == "personal")
        #expect(repo.activeAccountId(forProvider: "codex") == "work")
    }

    // MARK: - Key Pattern (JSONSettingsStore)

    @Test
    func `accounts are stored under providers dot id dot accounts`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")

        let raw: [Any]? = store.read(key: "providers.claude.accounts")
        #expect(raw?.count == 1)
        #expect((raw?.first as? [String: Any])?["accountId"] as? String == "personal")
    }

    @Test
    func `active account is stored under providers dot id dot activeAccountId`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        repo.setActiveAccountId("work", forProvider: "claude")

        #expect(store.read(key: "providers.claude.activeAccountId") == "work")
    }

    @Test
    func `an empty accounts array in the file reads as single-account`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        store.write(value: [Any](), key: "providers.claude.accounts")

        #expect(repo.accounts(forProvider: "claude").isEmpty)
    }

    @Test
    func `malformed account entries are skipped rather than failing the read`() {
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
    func `accounts survive a new repository over the same file`() {
        let (store, repo, dir) = makeStore()
        defer { cleanup(dir) }

        repo.addAccount(account("personal", label: "Personal"), forProvider: "claude")
        repo.setActiveAccountId("personal", forProvider: "claude")

        let reopened = JSONSettingsRepository(store: JSONSettingsStore(fileURL: store.fileURL))

        #expect(reopened.accounts(forProvider: "claude").map(\.accountId) == ["personal"])
        #expect(reopened.activeAccountId(forProvider: "claude") == "personal")
    }
}
