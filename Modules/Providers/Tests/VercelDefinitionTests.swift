import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Vercel AI Gateway as data: the credits balance is money with no ceiling,
/// the key and its environment variable are settings.
@MainActor @Suite
struct VercelDefinitionTests {
    private func make(body: String = #"{"balance":95.50,"total_used":4.50}"#, status: Int = 200,
                      environment: [String: String] = [:], vault: MemoryVault = MemoryVault(["vercel-gateway.apiKey": "personal"]),
                      settings: InMemoryProviderSettings = InMemoryProviderSettings(), replies: [String: String]? = nil) throws -> Provider {
        let definition = try ProviderFactory.builtIn("vercel-gateway")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            guard request.url?.absoluteString == "https://ai-gateway.vercel.sh/v1/credits", request.timeoutInterval == 30,
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
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, secrets: vault.scoped(to: login),
                             environment: { environment[$0] }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `should show Vercel Gateway with its dashboard, off until turned on, sending its key only to the gateway`() throws {
        let provider = try make()
        #expect(provider.id == "vercel-gateway")
        #expect(provider.name == "Vercel Gateway")
        #expect(!provider.plainIsInLineup)
        #expect(provider.definition.profile.links.dashboard == URL(string: "https://vercel.com/dashboard/ai-gateway"))
        #expect(provider.definition.accounts?.ways == [.form])
        #expect(provider.definition.keyDestinations == ["ai-gateway.vercel.sh"])
    }

    @Test(arguments: ["95.50", "0", "1245.67", "-1.25", "0.123456789"])
    func `should show the credit balance as exact dollars, with no ceiling, no percentage and no window`(_ amount: String) async throws {
        for value in [amount, "\"\(amount)\""] {
            let usage = try await make(body: "{\"balance\":\(value)}").refreshPlain()
            let quota = try #require(usage.quotas.first)
            #expect(quota.quotaType == .modelSpecific("AI Gateway Credits"))
            #expect(quota.left == .money(Money(Decimal(string: amount)!, currency: "USD"), of: nil))
            #expect(quota.percentLeft == nil)
            #expect(quota.window == nil)
        }
    }

    @Test(arguments: ["not JSON", "{}", #"{"balance":"abc"}"#, #"{"balance":"0x10"}"#, #"{"balance":null}"#, #"{"balance":true}"#])
    func `should fail at reading the answer when Vercel reports no readable balance`(_ body: String) async throws {
        let product = try make(body: body)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }

    @Test(arguments: [401, 403]) func `should ask to sign in again when Vercel refuses the key`(_ status: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(status: status).refreshPlain() }
    }

    @Test(arguments: [429, 500]) func `should fail at fetching when Vercel is rate-limiting or down`(_ status: Int) async throws {
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
    }

    @Test func `should use the environment key for the default login and each added login's own saved key`() async throws {
        let vault = MemoryVault(["vercel-gateway.apiKey": "personal"])
        let settings = InMemoryProviderSettings()
        let provider = try make(environment: ["AI_GATEWAY_API_KEY": "environment"], vault: vault, settings: settings,
                                replies: ["Bearer environment": #"{"balance":40}"#, "Bearer work": #"{"balance":"7.50"}"#])
        let work = try provider.accounts.add(filling: ["apiKey": "work"])
        #expect(!work.isPaused)
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 40)
        #expect(try await provider.refresh(work).quotas.first?.dollarRemaining == Decimal(string: "7.50"))
        #expect(settings.accounts(forProvider: provider.id).first?.probeConfig["apiKey"] == nil)
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await provider.refresh(work) }
    }

    @Test func `should use the key from the environment variable the person named`() async throws {
        let settings = InMemoryProviderSettings()
        settings.setValue("MY_GATEWAY_KEY", "authEnvVar", forProvider: "vercel-gateway")
        let provider = try make(environment: ["MY_GATEWAY_KEY": "named"], vault: MemoryVault(), settings: settings,
                                replies: ["Bearer named": #"{"balance":3}"#])
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 3)
    }

    @Test func `should use the saved key when the environment key is blank`() async throws {
        let provider = try make(environment: ["AI_GATEWAY_API_KEY": " \n "], replies: ["Bearer personal": #"{"balance":10}"#])
        #expect(try await provider.refreshPlain().quotas.first?.dollarRemaining == 10)
    }
}
