import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

@MainActor
@Suite
struct DeepSeekDefinitionTests {
    private let balance = #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"40.00","granted_balance":"10.00","topped_up_balance":"30.00"}]}"#

    private func make(body: String? = nil, status: Int = 200, vault: MemoryVault = MemoryVault(["deepseek.apiKey": "personal"]),
                      environment: [String: String] = [:], settings: InMemoryProviderSettings = InMemoryProviderSettings(),
                      balancesByKey: [String: String]? = nil) throws -> Provider {
        let definition = try ProviderFactory.builtIn("deepseek")
        let network = MockNetworkClient()
        let body = body ?? balance
        given(network).request(.any).willProduce { @Sendable request in
            guard request.url?.absoluteString == "https://api.deepseek.com/user/balance",
                  request.httpMethod == "GET", request.timeoutInterval == 30,
                  request.value(forHTTPHeaderField: "Accept") == "application/json" else {
                return (Data(), StubbedProvider.response(400))
            }
            if let balancesByKey {
                let key = request.value(forHTTPHeaderField: "Authorization") ?? ""
                guard let answer = balancesByKey[key] else { return (Data(), StubbedProvider.response(401)) }
                return (Data(answer.utf8), StubbedProvider.response(200))
            }
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: definition.id),
                        makeDataSource: { source, account in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: account), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test
    func `should be DeepSeek, out of the lineup until turned on, with its usage dashboard, icon and an add-login form`() throws {
        let provider = try make()
        #expect(provider.id == "deepseek")
        #expect(provider.name == "DeepSeek")
        #expect(provider.plainIsInLineup == false)
        #expect(provider.definition.profile.links.dashboard == URL(string: "https://platform.deepseek.com/usage"))
        #expect(provider.definition.profile.look.icon == "DeepSeekIcon")
        #expect(provider.definition.accounts?.ways == [.form])
    }

    @Test(.needsScriptEngine)
    func `should show the first balance exactly in its own currency, with the paid and granted parts, and no percentage`() async throws {
        let body = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.123456789","granted_balance":"10","topped_up_balance":"100"},{"currency":"USD","total_balance":"40"}]}"#
        let usage = try await make(body: body).refreshPlain()
        let quota = try #require(usage.quotas.first)
        #expect(usage.quotas.count == 1)
        #expect(quota.quotaType == .modelSpecific("Balance"))
        #expect(quota.left == .money(Money(Decimal(string: "110.123456789")!, currency: "CNY"), of: nil))
        #expect(quota.resetText == "Paid: ¥100.00 · Granted: ¥10.00")
        #expect(quota.percentLeft == nil)
        #expect(quota.window == nil)
    }

    @Test(.needsScriptEngine)
    func `should leave out a paid or granted part that is missing or unreadable`() async throws {
        let body = #"{"balance_infos":[{"currency":"USD","total_balance":"40","granted_balance":"bad","topped_up_balance":"30"}]}"#
        let usage = try await make(body: body).refreshPlain()
        #expect(usage.quotas.first?.resetText == "Paid: $30.00")
    }

    @Test(.needsScriptEngine)
    func `should read the default login with the environment key and each added login with its own key`() async throws {
        let vault = MemoryVault(["deepseek.apiKey": "personal"])
        let replies = ["Bearer environment": #"{"balance_infos":[{"currency":"USD","total_balance":"40"}]}"#,
                       "Bearer work": #"{"balance_infos":[{"currency":"CNY","total_balance":"7"}]}"#]
        let provider = try make(vault: vault, environment: ["DEEPSEEK_API_KEY": "environment"], balancesByKey: replies)
        let work = try provider.accounts.add(filling: ["apiKey": "work"])
        #expect(!work.isPaused)
        let personalUsage = try await provider.refreshPlain()
        let workUsage = try await provider.refresh(work)
        #expect(personalUsage.quotas.first?.left == .money(Money(40, currency: "USD"), of: nil))
        #expect(workUsage.quotas.first?.left == .money(Money(7, currency: "CNY"), of: nil))
        #expect(workUsage.providerId == work.id)
    }

    @Test(.needsScriptEngine)
    func `should read the key from the environment variable the person named`() async throws {
        let settings = InMemoryProviderSettings()
        settings.setValue("MY_DEEPSEEK", "authEnvVar", forProvider: "deepseek")
        let provider = try make(environment: ["MY_DEEPSEEK": "named", "DEEPSEEK_API_KEY": "default"], settings: settings,
                                balancesByKey: ["Bearer named": balance])
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 40)
    }

    @Test(.needsScriptEngine)
    func `should read DEEPSEEK_API_KEY when the person named no variable`() async throws {
        let settings = InMemoryProviderSettings()
        settings.setValue("", "authEnvVar", forProvider: "deepseek")
        let provider = try make(environment: ["DEEPSEEK_API_KEY": "default"], settings: settings,
                                balancesByKey: ["Bearer default": balance])
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 40)
    }

    @Test(.needsScriptEngine)
    func `should use the saved key when the environment key is empty`() async throws {
        let provider = try make(environment: ["DEEPSEEK_API_KEY": ""], balancesByKey: ["Bearer personal": balance])
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 40)
    }

    @Test
    func `should be unavailable and ask for a key when the default login has none`() async throws {
        let product = try make(vault: MemoryVault())
        let account = product.defaultAccount
        #expect(await product.isAvailable(account) == false)
        await #expect(throws: UsageError.authenticationRequired) { try await product.refresh(account) }
    }

    @Test(.needsScriptEngine, arguments: ["0", "-1.25"])
    func `should show a zero or negative balance as depleted, with no made-up percentage`(_ amount: String) async throws {
        let body = #"{"balance_infos":[{"currency":"USD","total_balance":"\#(amount)"}]}"#
        let usage = try await make(body: body).refreshPlain()
        #expect(usage.quotas.first?.status == .depleted)
        #expect(usage.quotas.first?.percentLeft == nil)
    }

    @Test(arguments: [429, 500])
    func `should fail at fetching when DeepSeek is rate limited or errors`(_ status: Int) async throws {
        let product = try make(status: status)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .fetch)
    }

    @Test(arguments: [401, 403])
    func `should ask for a key when DeepSeek refuses it`(_ status: Int) async throws {
        let product = try make(status: status)
        let account = product.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await product.refresh(account) }
    }

    @Test(.needsScriptEngine)
    func `should report no data when DeepSeek lists no balance`() async throws {
        let product = try make(body: #"{"balance_infos":[]}"#)
        let account = product.defaultAccount
        await #expect(throws: UsageError.noData) { try await product.refresh(account) }
    }

    @Test(arguments: ["not JSON", #"{"balance_infos":[{"currency":"USD","total_balance":"bad"}]}"#])
    func `should fail reading the balance when it is unreadable`(_ body: String) async throws {
        let product = try make(body: body)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }

    @Test(.needsScriptEngine)
    func `should say the balance is unavailable for API calls rather than show it healthy`() async throws {
        let product = try make(body: #"{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"5"}]}"#)
        let account = product.defaultAccount
        await #expect(throws: UsageError.executionFailed("DeepSeek reports that this balance is unavailable for API calls.")) { try await product.refresh(account) }
    }

    @Test(.needsScriptEngine)
    func `should keep an added login's key out of settings and never fall back to the default key`() async throws {
        let vault = MemoryVault(["deepseek.apiKey": "personal"])
        let settings = InMemoryProviderSettings()
        let provider = try make(vault: vault, environment: ["DEEPSEEK_API_KEY": "environment-default"], settings: settings)
        let work = try provider.accounts.add(filling: ["apiKey": "work"])
        #expect(settings.accounts(forProvider: "deepseek").first?.probeConfig["apiKey"] == nil)
        #expect(vault.secrets["\(work.id).apiKey"] == "work")
        let reloaded = try make(vault: vault, settings: settings)
        #expect(!reloaded.accounts[1].isPaused)
        let usage = try await reloaded.refresh(reloaded.accounts[1])
        #expect(usage.providerId == work.id)
        reloaded.accounts[1].isPaused = true
        #expect(try make(vault: vault, settings: settings).accounts[1].isPaused)
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await provider.refresh(work) }
        #expect(work.lastFailedStep == .lookup)
    }
}
