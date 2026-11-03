import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// OpenRouter as data: the credits balance is the lifetime credit minus the
/// usage, money with no ceiling, the key and its environment variable are
/// settings.
@MainActor @Suite
struct OpenRouterDefinitionTests {
    private func make(body: String = #"{"data":{"total_credits":"10.00","total_usage":"3.50"}}"#, status: Int = 200,
                      environment: [String: String] = [:], vault: MemoryVault = MemoryVault(["openrouter.apiKey": "personal"]),
                      settings: InMemoryProviderSettings = InMemoryProviderSettings(), replies: [String: String]? = nil) throws -> Provider {
        let definition = try ProviderFactory.builtIn("openrouter")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            guard request.url?.absoluteString == "https://openrouter.ai/api/v1/credits", request.timeoutInterval == 30,
                  request.value(forHTTPHeaderField: "Accept") == "application/json" else { return (Data(), StubbedProvider.response(400)) }
            if let replies {
                guard let response = replies[request.value(forHTTPHeaderField: "Authorization") ?? ""] else {
                    return (Data(), StubbedProvider.response(401))
                }
                return (Data(response.utf8), StubbedProvider.response(200))
            }
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: definition.id),
                        makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login),
                             environment: { environment[$0] }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    /// A report whose credit minus usage is `remaining`, with the rest used.
    private func report(remaining: String) -> String {
        let total = Decimal(string: "10.00")!
        let used = total - Decimal(string: remaining)!
        return #"{"data":{"total_credits":"10.00","total_usage":"\#(used.description)"}}"#
    }

    /// The mapping script's `usd`: exact money rounded to cents, half up.
    private func cents(_ amount: Decimal) -> String {
        let rounded = NSDecimalNumber(decimal: amount).rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
        return String(format: "%.2f", rounded.doubleValue)
    }

    @Test func `should show OpenRouter with its credits dashboard and status page, off until turned on`() throws {
        let provider = try make()
        #expect(provider.id == "openrouter")
        #expect(provider.name == "OpenRouter")
        #expect(!provider.plainIsInLineup)
        #expect(provider.definition.profile.links.dashboard == URL(string: "https://openrouter.ai/credits"))
        #expect(provider.definition.profile.links.status == URL(string: "https://status.openrouter.ai"))
        #expect(provider.definition.profile.look.icon == "OpenRouterIcon")
        #expect(provider.definition.profile.look.symbol == "arrow.triangle.branch")
        #expect(provider.definition.accounts?.ways == [.form])
    }

    @Test(arguments: ["6.50", "0", "1245.67", "-1.25", "0.005"])
    func `should show the credits left after usage as exact dollars, with no ceiling, no percentage and no window`(_ remaining: String) async throws {
        let usage = try await make(body: report(remaining: remaining)).refreshPlain()
        let quota = try #require(usage.quotas.first)
        #expect(usage.quotas.count == 1)
        #expect(quota.quotaType == .modelSpecific("Credits"))
        #expect(quota.left == .money(Money(Decimal(string: remaining)!, currency: "USD"), of: nil))
        #expect(quota.percentLeft == nil)
        #expect(quota.window == nil)
        let used = Decimal(string: "10.00")! - Decimal(string: remaining)!
        #expect(quota.resetText == "Total: $\(cents(Decimal(string: "10.00")!)) · Used: $\(cents(used))")
    }

    @Test func `should show the credits left when OpenRouter reports amounts as numbers`() async throws {
        let numbers = try await make(body: #"{"data":{"total_credits":10,"total_usage":3.5}}"#).refreshPlain()
        #expect(numbers.quotas.first?.left == .money(Money(Decimal(string: "6.5")!, currency: "USD"), of: nil))
    }

    @Test(arguments: ["0", "-1.25"])
    func `should show the credits depleted, with no percentage, when they are spent or overdrawn`(_ remaining: String) async throws {
        let usage = try await make(body: report(remaining: remaining)).refreshPlain()
        #expect(usage.quotas.first?.status == .depleted)
        #expect(usage.quotas.first?.percentLeft == nil)
    }

    @Test(arguments: ["not JSON", "{}", #"{"data":{}}"#, #"{"data":{"total_credits":"10"}}"#,
                      #"{"data":{"total_credits":"abc","total_usage":"1"}}"#, #"{"data":{"total_credits":"10","total_usage":"0x1"}}"#,
                      #"{"data":[1]}"#, #"{"data":null}"#])
    func `should fail at reading the answer when OpenRouter reports no readable credits`(_ body: String) async throws {
        let product = try make(body: body)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }

    @Test func `should ask to sign in again when OpenRouter refuses the key`() async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(status: 401).refreshPlain() }
    }

    @Test func `should say the credits need a Management key when OpenRouter forbids a regular key`() async throws {
        let product = try make(body: #"{"error":{"code":403,"message":"Only management keys can perform this operation"}}"#, status: 403)
        let account = product.defaultAccount
        await #expect(throws: UsageError.executionFailed(
            "OpenRouter shows credits only to a Management key; a regular API key gets 403. Create one at openrouter.ai/settings/management-keys and paste it as the key. On the default account, a key in the environment variable (OPENROUTER_API_KEY by default) is used first: unset it or change the Environment variable setting. An added account uses only its own saved key.")) {
            try await product.refresh(account)
        }
        #expect(account.lastFailedStep == .fetch)
    }

    @Test(arguments: [429, 500]) func `should fail at fetching when OpenRouter is rate-limiting or down`(_ status: Int) async throws {
        let product = try make(status: status)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .fetch)
    }

    @Test func `should be unavailable and ask for a key when none is saved or set`() async throws {
        let product = try make(vault: MemoryVault())
        let account = product.defaultAccount
        #expect(await product.isAvailable(account) == false)
        await #expect(throws: UsageError.authenticationRequired) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test func `should use the environment key for the default login and each added login's own saved key`() async throws {
        let vault = MemoryVault(["openrouter.apiKey": "personal"])
        let settings = InMemoryProviderSettings()
        let provider = try make(environment: ["OPENROUTER_API_KEY": "environment"], vault: vault, settings: settings,
                                replies: ["Bearer environment": #"{"data":{"total_credits":"40","total_usage":"0"}}"#,
                                          "Bearer work": #"{"data":{"total_credits":"7.50","total_usage":"0"}}"#])
        let work = try provider.accounts.add(filling: ["apiKey": "work"])
        #expect(!work.isPaused)
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 40)
        #expect(try await provider.refresh(work).quotas.first?.dollarRemaining == Decimal(string: "7.50"))
        #expect(settings.accounts(forProvider: provider.id).first?.probeConfig["apiKey"] == nil)
        #expect(vault.secrets["\(work.id).apiKey"] == "work")
    }

    @Test func `should use the key from the environment variable the person named`() async throws {
        let replies = ["Bearer named": #"{"data":{"total_credits":"40","total_usage":"0"}}"#,
                       "Bearer default": #"{"data":{"total_credits":"1","total_usage":"0"}}"#]
        let settings = InMemoryProviderSettings()
        settings.setValue("ROUTER_KEY", "authEnvVar", forProvider: "openrouter")
        let provider = try make(environment: ["OPENROUTER_API_KEY": "default", "ROUTER_KEY": "named"],
                                settings: settings, replies: replies)
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 40)
    }
}
