import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// MiniMax as data: the old probe's fixtures through `minimax.json`, quota for
/// quota, with its region, key and environment variable as settings.
@MainActor @Suite
struct MiniMaxDefinitionTests {
    static let sampleSuccessResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    /// Token Plan responses carry percentages; the count fields are 0 there.
    static let sampleTokenPlanResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "general",
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "current_interval_remaining_percent": 100,
          "current_weekly_remaining_percent": 98,
          "start_time": 1787673600000,
          "end_time": 1787691600000,
          "weekly_start_time": 1787500800000,
          "weekly_end_time": 1788105600000
        },
        {
          "model_name": "video",
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "current_interval_remaining_percent": 100,
          "current_weekly_remaining_percent": 100,
          "start_time": 1787673600000,
          "end_time": 1787760000000,
          "weekly_start_time": 1787500800000,
          "weekly_end_time": 1788105600000
        }
      ]
    }
    """

    static let sampleMultiModelResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        },
        {
          "model_name": "minimax-m1",
          "current_interval_total_count": 500,
          "current_interval_usage_count": 400,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    static let sampleErrorResponse = """
    {
      "base_resp": { "status_code": 1001, "status_msg": "invalid api key" },
      "model_remains": []
    }
    """

    static let sampleEmptyRemainsResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": []
    }
    """

    static let sampleNoEndTimeResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1000,
          "current_interval_usage_count": 500
        }
      ]
    }
    """


    /// MiniMax on stubbed connections. The stub answers only on the region's
    /// host and path, with the 30-second timeout the old probe used.
    private func make(body: String = sampleSuccessResponse, status: Int = 200, region: String? = "china",
                      authEnvVar: String? = nil, vault: MemoryVault = MemoryVault(["minimax.apiKey": "personal"]),
                      environment: [String: String] = [:]) throws -> Provider {
        let definition = try ProviderFactory.builtIn("minimax")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            let international = request.value(forHTTPHeaderField: "Authorization") == "Bearer work" || region == "international"
            guard request.url?.host == (international ? "api.minimax.io" : "api.minimaxi.com"),
                  request.url?.path == "/v1/token_plan/remains", request.timeoutInterval == 30 else {
                return (Data(), StubbedProvider.response(400))
            }
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        // Saved where the old card saved them: `minimax.region`, `minimax.authEnvVar`.
        let settings = InMemoryProviderSettings()
        settings.setValue(region, "region", forProvider: "minimax")
        settings.setValue(authEnvVar, "authEnvVar", forProvider: "minimax")
        return Provider(definition: definition, settings: settings, makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `should show MiniMax off until turned on, sending its key only to MiniMax's hosts and adding logins by form`() throws {
        let provider = try make()
        #expect(provider.name == "MiniMax")
        #expect(!provider.plainIsInLineup)
        #expect(provider.definition.keyDestinations == ["api.minimax.io", "api.minimaxi.com"])
        #expect(provider.definition.accounts?.ways == [.form])
    }

    @Test func `should show 17% left and 1245/1500 requests used when MiniMax counts the requests remaining`() async throws {
        let quota = try #require(try await make().refreshPlain().quotas.first)
        #expect(quota.percentRemaining == 17)
        #expect(quota.quotaType == .modelSpecific("minimax-m2"))
        #expect(quota.resetText == "1245/1500 requests")
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1735689600))
        #expect(quota.window?.length == nil)
    }

    @Test func `should show a 5-hour and a weekly window for each model when MiniMax answers with Token Plan percentages`() async throws {
        let quotas = try await make(body: Self.sampleTokenPlanResponse).refreshPlain().quotas
        #expect(quotas.count == 4)
        #expect(quotas.map(\.percentRemaining) == [100, 98, 100, 100])
        #expect(quotas[1].quotaType == .timeLimit("general Weekly"))
        #expect(quotas[0].window?.length == 18000)
        #expect(quotas[1].window?.length == 604800)
        #expect(quotas[1].resetText == "2% used")
    }

    @Test func `should show each model's quota, and no reset when MiniMax gives no end time`() async throws {
        #expect(try await make(body: Self.sampleMultiModelResponse).refreshPlain().quotas.map(\.percentRemaining) == [17, 80])
        let quota = try #require(try await make(body: Self.sampleNoEndTimeResponse).refreshPlain().quotas.first)
        #expect(quota.percentRemaining == 50)
        #expect(quota.resetsAt == nil)
    }

    @Test func `should fail with MiniMax's own message, or with no data, when MiniMax reports an error or no models`() async throws {
        await #expect(throws: UsageError.executionFailed("MiniMax API error: invalid api key")) {
            try await make(body: Self.sampleErrorResponse).refreshPlain()
        }
        await #expect(throws: UsageError.noData) { try await make(body: Self.sampleEmptyRemainsResponse).refreshPlain() }
        await #expect(throws: UsageError.noData) { try await make(body: #"{"base_resp":{"status_code":0}}"#).refreshPlain() }
    }

    @Test(arguments: ["not JSON", #"{"base_resp":{"status_code":0},"model_remains":[{}]}"#])
    func `should fail at reading the answer when MiniMax answers with something unreadable`(_ body: String) async throws {
        let provider = try make(body: body)
        await #expect(throws: UsageError.self) { try await provider.refreshPlain() }
        #expect(provider.defaultAccount.lastFailedStep == .mapping)
    }

    @Test func `should show no data when MiniMax reports neither a count nor a percentage left`() async throws {
        let body = #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_total_count":0,"current_interval_usage_count":0}]}"#
        await #expect(throws: UsageError.noData) { try await make(body: body).refreshPlain() }
    }

    @Test(arguments: ["china", "international"])
    func `should ask the saved region's MiniMax and open its dashboard`(_ region: String) async throws {
        let provider = try make(region: region)
        #expect(try await provider.refreshPlain().quotas.count == 1)
        #expect(provider.plainDashboardURL?.host == (region == "international" ? "platform.minimax.io" : "platform.minimaxi.com"))
    }

    @Test func `should ask MiniMax China when no region is saved`() async throws {
        let provider = try make(region: nil)
        #expect(try await provider.refreshPlain().quotas.count == 1)
    }

    @Test func `should use the key from the environment variable the person named`() async throws {
        let provider = try make(authEnvVar: "MY_MINIMAX_KEY", vault: MemoryVault(), environment: ["MY_MINIMAX_KEY": "personal"])
        #expect(try await provider.refreshPlain().quotas.count == 1)
    }

    @Test func `should show in Settings where the key is looked for, naming the person's own variable`() throws {
        #expect(try make().configuration.definitionAsRun.dataSource("api")?.credential?.lookupOrder == ["$MINIMAX_API_KEY", "API key saved in ClaudeBar"])
        #expect(try make(authEnvVar: "MY_MINIMAX_KEY").configuration.definitionAsRun.dataSource("api")?.credential?.lookupOrder.first == "$MY_MINIMAX_KEY")
    }

    @Test func `should use MINIMAX_API_KEY when the named environment variable is empty`() async throws {
        let provider = try make(authEnvVar: "", vault: MemoryVault(), environment: ["MINIMAX_API_KEY": "personal"])
        #expect(try await provider.refreshPlain().quotas.count == 1)
    }

    @Test func `should use an added login's own key and region, never the environment, and ask to sign in when its key is gone`() async throws {
        let vault = MemoryVault(["minimax.apiKey": "personal"])
        let provider = try make(vault: vault, environment: ["MINIMAX_API_KEY": "environment"])
        let work = try provider.accounts.add(filling: ["apiKey": "work", "region": "international"])
        #expect(!work.isPaused)
        #expect(try await provider.refresh(work).quotas.first?.percentRemaining == 17)
        #expect(provider.dashboardURL(of: work)?.host == "platform.minimax.io")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await provider.refresh(work) }
    }

    @Test(arguments: [401, 403]) func `should ask to sign in again when MiniMax refuses the key`(_ code: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(status: code).refreshPlain() }
    }

    @Test(arguments: [429, 500]) func `should fail at fetching when MiniMax is rate-limiting or down`(_ code: Int) async throws {
        let product = try make(status: code)
        let account = product.defaultAccount
        await #expect(throws: UsageError.self) { try await product.refresh(account) }
        #expect(account.lastFailedStep == .fetch)
    }
}
