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
        let definition = try Providers.builtIn("deepseek")
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
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: Providers.builtInScripts,
                             secrets: vault.scoped(to: account), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test
    func `the bundled definition keeps the existing identity links and disabled default`() throws {
        let provider = try make()
        #expect(provider.id == "deepseek")
        #expect(provider.name == "DeepSeek")
        #expect(provider.defaultAccount.isEnabled == false)
        #expect(provider.definition.profile.links.dashboard == URL(string: "https://platform.deepseek.com/usage"))
        #expect(provider.definition.profile.look.icon == "DeepSeekIcon")
        #expect(provider.definition.accounts?.ways == [.form])
    }

    @Test
    func `the first balance keeps its currency exact money and paid granted details`() async throws {
        let body = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.123456789","granted_balance":"10","topped_up_balance":"100"},{"currency":"USD","total_balance":"40"}]}"#
        let usage = try await make(body: body).defaultAccount.refresh()
        let quota = try #require(usage.quotas.first)
        #expect(usage.quotas.count == 1)
        #expect(quota.quotaType == .modelSpecific("Balance"))
        #expect(quota.left == .money(Money(Decimal(string: "110.123456789")!, currency: "CNY"), of: nil))
        #expect(quota.resetText == "Paid: ¥100.00 · Granted: ¥10.00")
        #expect(quota.percentLeft == nil)
        #expect(quota.window == nil)
    }

    @Test
    func `optional breakdown fields can be missing or invalid`() async throws {
        let body = #"{"balance_infos":[{"currency":"USD","total_balance":"40","granted_balance":"bad","topped_up_balance":"30"}]}"#
        let usage = try await make(body: body).defaultAccount.refresh()
        #expect(usage.quotas.first?.resetText == "Paid: $30.00")
    }

    @Test
    func `the default environment key takes priority and each added account sends its own key`() async throws {
        let vault = MemoryVault(["deepseek.apiKey": "personal"])
        let replies = ["Bearer environment": #"{"balance_infos":[{"currency":"USD","total_balance":"40"}]}"#,
                       "Bearer work": #"{"balance_infos":[{"currency":"CNY","total_balance":"7"}]}"#]
        let provider = try make(vault: vault, environment: ["DEEPSEEK_API_KEY": "environment"], balancesByKey: replies)
        let work = try provider.addAccount(filling: ["apiKey": "work"])
        #expect(work.isEnabled)
        let personalUsage = try await provider.defaultAccount.refresh()
        let workUsage = try await work.refresh()
        #expect(personalUsage.quotas.first?.left == .money(Money(40, currency: "USD"), of: nil))
        #expect(workUsage.quotas.first?.left == .money(Money(7, currency: "CNY"), of: nil))
        #expect(workUsage.providerId == work.id)
    }

    @Test
    func `an empty environment key falls back to the saved default key`() async throws {
        let provider = try make(environment: ["DEEPSEEK_API_KEY": ""], balancesByKey: ["Bearer personal": balance])
        #expect(try await provider.defaultAccount.refresh().quotas.first?.dollarRemaining == 40)
    }

    @Test
    func `an unsigned default account is unavailable`() async throws {
        let account = try make(vault: MemoryVault()).defaultAccount
        #expect(await account.isAvailable() == false)
        await #expect(throws: UsageError.authenticationRequired) { try await account.refresh() }
    }

    @Test(arguments: ["0", "-1.25"])
    func `zero and negative balances are depleted without inventing a cap`(_ amount: String) async throws {
        let body = #"{"balance_infos":[{"currency":"USD","total_balance":"\#(amount)"}]}"#
        let usage = try await make(body: body).defaultAccount.refresh()
        #expect(usage.quotas.first?.status == .depleted)
        #expect(usage.quotas.first?.percentLeft == nil)
    }

    @Test(arguments: [429, 500])
    func `HTTP failures remain fetch failures`(_ status: Int) async throws {
        let account = try make(status: status).defaultAccount
        await #expect(throws: UsageError.self) { try await account.refresh() }
        #expect(account.lastFailedStep == .fetch)
    }

    @Test(arguments: [401, 403])
    func `rejected keys fail authentication`(_ status: Int) async throws {
        let account = try make(status: status).defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await account.refresh() }
    }

    @Test
    func `an empty balance list has no data`() async throws {
        let account = try make(body: #"{"balance_infos":[]}"#).defaultAccount
        await #expect(throws: UsageError.noData) { try await account.refresh() }
    }

    @Test(arguments: ["not JSON", #"{"balance_infos":[{"currency":"USD","total_balance":"bad"}]}"#])
    func `malformed balances fail at mapping`(_ body: String) async throws {
        let account = try make(body: body).defaultAccount
        await #expect(throws: UsageError.self) { try await account.refresh() }
        #expect(account.lastFailedStep == .mapping)
    }

    @Test
    func `unusable funds are an explicit failure rather than a healthy balance`() async throws {
        let account = try make(body: #"{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"5"}]}"#).defaultAccount
        await #expect(throws: UsageError.executionFailed("DeepSeek reports that this balance is unavailable for API calls.")) { try await account.refresh() }
    }

    @Test
    func `form accounts keep their keys out of settings and never borrow the default key`() async throws {
        let vault = MemoryVault(["deepseek.apiKey": "personal"])
        let settings = InMemoryProviderSettings()
        let provider = try make(vault: vault, environment: ["DEEPSEEK_API_KEY": "environment-default"], settings: settings)
        let work = try provider.addAccount(filling: ["apiKey": "work"])
        #expect(settings.accounts(forProvider: "deepseek").first?.probeConfig["apiKey"] == nil)
        #expect(vault.secrets["\(work.id).apiKey"] == "work")
        let reloaded = try make(vault: vault, settings: settings)
        #expect(reloaded.accounts[1].isEnabled)
        let usage = try await reloaded.accounts[1].refresh()
        #expect(usage.providerId == work.id)
        reloaded.accounts[1].isEnabled = false
        #expect(try make(vault: vault, settings: settings).accounts[1].isEnabled == false)
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await work.refresh() }
        #expect(work.lastFailedStep == .lookup)
    }
}
