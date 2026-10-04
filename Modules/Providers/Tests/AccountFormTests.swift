import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// *Add Account* by its form: a provider whose key is the person's own — an
/// API someone added — takes a second account by a second key. That key lives
/// in the account's own corner of the vault; a login without one of its own
/// is *Key needed*, never the default login's key.
@MainActor
@Suite
struct AccountFormTests {
    /// Ken's OpenRouter, made in Add Provider: his key, money of a limit.
    private func openRouter() throws -> ProviderDefinition {
        var draft = ProviderDraft(start: .api)
        draft.url = "https://openrouter.ai/api/v1/auth/key"
        draft.key = .apiKey
        draft.sentAs = .bearer
        draft.measure = .money(currency: "USD")
        draft.remaining = "$.data.limit_remaining"
        draft.limit = "$.data.limit"
        draft.name = "OpenRouter"
        return try draft.definition(id: "custom-openrouter")
    }

    /// Answers by key: each account sees the money left on its own key.
    private func network(_ remaining: [String: Int]) -> MockNetworkClient {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            let key = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
            guard let left = remaining[key] else {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(#"{"data":{"limit_remaining":\#(left),"limit":50}}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return network
    }

    private func provider(_ definition: ProviderDefinition, vault: MemoryVault, network: MockNetworkClient,
                          settings: InMemoryProviderSettings = InMemoryProviderSettings()) -> Provider {
        Provider(
            definition: definition,
            settings: settings,
            accounts: settings.accounts(forProvider: definition.id),
            makeDataSource: { source, account in
                DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                                 makeTransport: { _, _, _, _ in MockRPCTransport() }, secrets: vault.scoped(to: account),
                                 environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
            },
            vault: vault
        )
    }

    // MARK: - The form, from the definition

    @Test
    func `an API someone added asks a second account for its own key`() throws {
        let accounts = try #require(try openRouter().accounts)

        #expect(accounts.ways == [.form])
        #expect(accounts.form.map(\.id) == ["apiKey"])
        #expect(accounts.form.first?.kind == .secret)
    }

    @Test
    func `a key read from an environment variable is the default login's; an added one types its own`() throws {
        var draft = ProviderDraft(start: .api)
        draft.url = "https://example.test/usage"
        draft.key = .environment("EXAMPLE_API_KEY")
        draft.measure = .percentUsed
        draft.used = "$.used"
        draft.name = "Example"
        let definition = try draft.definition(id: "custom-example")

        let added = try #require(try definition.dataSources(forAccount: [:]).first)

        #expect(definition.dataSources.first?.credential == .environment("EXAMPLE_API_KEY"))
        #expect(added.credential == .setting("apiKey"))
    }

    // MARK: - Each account, its own key

    @Test
    func `an account added by its form reads its own key`() async throws {
        let vault = MemoryVault(["custom-openrouter.apiKey": "sk-mine"])
        let openRouter = provider(try openRouter(), vault: vault, network: network(["sk-mine": 40, "sk-work": 7]))

        let work = try openRouter.addAccount(filling: ["apiKey": "sk-work"])
        let theirs = try await work.refresh()
        let mine = try await openRouter.defaultAccount.refresh()

        #expect(theirs.quotas.first?.left == .money(Money(7, currency: "USD"), of: Money(50, currency: "USD")))
        #expect(mine.quotas.first?.left == .money(Money(40, currency: "USD"), of: Money(50, currency: "USD")))
        #expect(work.madeBy == .form)
    }

    @Test
    func `a key is kept in the vault, never in the saved account`() throws {
        let vault = MemoryVault()
        let settings = InMemoryProviderSettings()
        let openRouter = provider(try openRouter(), vault: vault, network: network([:]), settings: settings)

        let work = try openRouter.addAccount(filling: ["apiKey": "sk-work"])

        #expect(vault.secrets["\(work.id).apiKey"] == "sk-work")
        #expect(settings.accounts(forProvider: "custom-openrouter").first?.probeConfig["apiKey"] == nil)
    }

    @Test
    func `an account without its own key never borrows the default's`() async throws {
        let vault = MemoryVault(["custom-openrouter.apiKey": "sk-mine"])
        let openRouter = provider(try openRouter(), vault: vault, network: network(["sk-mine": 40]))
        let work = try openRouter.addAccount(filling: ["apiKey": "sk-work"])
        vault.secrets["\(work.id).apiKey"] = nil

        await #expect(throws: (any Error).self) { try await work.refresh() }

        #expect(work.lastFailedStep == .lookup)
    }

    @Test
    func `a field left empty is refused, and nothing is added`() throws {
        let openRouter = provider(try openRouter(), vault: MemoryVault(), network: network([:]))

        #expect(throws: UsageError.self) { try openRouter.addAccount(filling: ["apiKey": "  "]) }
        #expect(openRouter.accounts.count == 1)
    }

    @Test
    func `removing an account forgets its keys`() throws {
        let vault = MemoryVault()
        let openRouter = provider(try openRouter(), vault: vault, network: network([:]))
        let work = try openRouter.addAccount(filling: ["apiKey": "sk-work"])

        openRouter.remove(work)

        #expect(vault.secrets["\(work.id).apiKey"] == nil)
    }

    @Test
    func `a saved form account comes back with its key after a relaunch`() async throws {
        let vault = MemoryVault()
        let settings = InMemoryProviderSettings()
        let first = provider(try openRouter(), vault: vault, network: network(["sk-work": 7]), settings: settings)
        try first.addAccount(filling: ["apiKey": "sk-work"])

        let relaunched = provider(try openRouter(), vault: vault, network: network(["sk-work": 7]), settings: settings)
        let usage = try await relaunched.accounts[1].refresh()

        #expect(usage.quotas.first?.left == .money(Money(7, currency: "USD"), of: Money(50, currency: "USD")))
    }
}
