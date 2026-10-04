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
        let definition = try Providers.builtIn("minimax")
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
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: Providers.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `definition keeps identity and opt-in default`() throws {
        let provider = try make()
        #expect(provider.name == "MiniMax")
        #expect(!provider.defaultAccount.isEnabled)
        #expect(provider.definition.keyDestinations == ["api.minimax.io", "api.minimaxi.com"])
        #expect(provider.definition.accounts?.ways == [.form])
    }

    @Test func `legacy counts are remaining and produce the original usage subtitle`() async throws {
        let quota = try #require(try await make().defaultAccount.refresh().quotas.first)
        #expect(quota.percentRemaining == 17)
        #expect(quota.quotaType == .modelSpecific("minimax-m2"))
        #expect(quota.resetText == "1245/1500 requests")
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1735689600))
        #expect(quota.window?.length == nil)
    }

    @Test func `Token Plan percentages produce independent interval and weekly windows`() async throws {
        let quotas = try await make(body: Self.sampleTokenPlanResponse).defaultAccount.refresh().quotas
        #expect(quotas.count == 4)
        #expect(quotas.map(\.percentRemaining) == [100, 98, 100, 100])
        #expect(quotas[1].quotaType == .timeLimit("general Weekly"))
        #expect(quotas[0].window?.length == 18000)
        #expect(quotas[1].window?.length == 604800)
        #expect(quotas[1].resetText == "2% used")
    }

    @Test func `all original model and optional reset fixtures survive`() async throws {
        #expect(try await make(body: Self.sampleMultiModelResponse).defaultAccount.refresh().quotas.map(\.percentRemaining) == [17, 80])
        let quota = try #require(try await make(body: Self.sampleNoEndTimeResponse).defaultAccount.refresh().quotas.first)
        #expect(quota.percentRemaining == 50)
        #expect(quota.resetsAt == nil)
    }

    @Test func `body-level API errors and empty responses remain failures`() async throws {
        await #expect(throws: UsageError.executionFailed("MiniMax API error: invalid api key")) {
            try await make(body: Self.sampleErrorResponse).defaultAccount.refresh()
        }
        await #expect(throws: UsageError.noData) { try await make(body: Self.sampleEmptyRemainsResponse).defaultAccount.refresh() }
        await #expect(throws: UsageError.noData) { try await make(body: #"{"base_resp":{"status_code":0}}"#).defaultAccount.refresh() }
    }

    @Test(arguments: ["not JSON", #"{"base_resp":{"status_code":0},"model_remains":[{}]}"#])
    func `malformed response fails mapping`(_ body: String) async throws {
        let account = try make(body: body).defaultAccount
        await #expect(throws: UsageError.self) { try await account.refresh() }
        #expect(account.lastFailedStep == .mapping)
    }

    @Test func `no reported remaining amount has no data`() async throws {
        let body = #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_total_count":0,"current_interval_usage_count":0}]}"#
        await #expect(throws: UsageError.noData) { try await make(body: body).defaultAccount.refresh() }
    }

    @Test(arguments: ["china", "international"])
    func `the saved region selects its endpoint and dashboard`(_ region: String) async throws {
        let provider = try make(region: region)
        #expect(try await provider.defaultAccount.refresh().quotas.count == 1)
        #expect(provider.defaultAccount.dashboardURL?.host == (region == "international" ? "platform.minimax.io" : "platform.minimaxi.com"))
    }

    @Test func `no saved region is China, as before`() async throws {
        let provider = try make(region: nil)
        #expect(try await provider.defaultAccount.refresh().quotas.count == 1)
    }

    @Test func `the key is read from the environment variable the person named`() async throws {
        let provider = try make(authEnvVar: "MY_MINIMAX_KEY", vault: MemoryVault(), environment: ["MY_MINIMAX_KEY": "personal"])
        #expect(try await provider.defaultAccount.refresh().quotas.count == 1)
    }

    @Test func `Settings prints the lookup order with the variable's own name`() throws {
        #expect(try make().definitionAsRun.dataSource("api")?.credential?.lookupOrder == ["$MINIMAX_API_KEY", "API key saved in ClaudeBar"])
        #expect(try make(authEnvVar: "MY_MINIMAX_KEY").definitionAsRun.dataSource("api")?.credential?.lookupOrder.first == "$MY_MINIMAX_KEY")
    }

    @Test func `an empty environment variable name means MINIMAX_API_KEY`() async throws {
        let provider = try make(authEnvVar: "", vault: MemoryVault(), environment: ["MINIMAX_API_KEY": "personal"])
        #expect(try await provider.defaultAccount.refresh().quotas.count == 1)
    }

    @Test func `work account has its own region key and no environment fallback`() async throws {
        let vault = MemoryVault(["minimax.apiKey": "personal"])
        let provider = try make(vault: vault, environment: ["MINIMAX_API_KEY": "environment"])
        let work = try provider.addAccount(filling: ["apiKey": "work", "region": "international"])
        #expect(work.isEnabled)
        #expect(try await work.refresh().quotas.first?.percentRemaining == 17)
        #expect(work.dashboardURL?.host == "platform.minimax.io")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.authenticationRequired) { try await work.refresh() }
    }

    @Test(arguments: [401, 403]) func `invalid keys require authentication`(_ code: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(status: code).defaultAccount.refresh() }
    }

    @Test(arguments: [429, 500]) func `HTTP failures remain fetch failures`(_ code: Int) async throws {
        let account = try make(status: code).defaultAccount
        await #expect(throws: UsageError.self) { try await account.refresh() }
        #expect(account.lastFailedStep == .fetch)
    }
}
