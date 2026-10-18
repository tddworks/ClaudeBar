import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Copilot as data: GitHub's billing API (a fine-grained token and the
/// username it bills) or the Copilot API (a classic token), each read by its
/// own script — the old probes' fixtures, quota for quota.
@MainActor @Suite
struct CopilotDefinitionTests {
    nonisolated static func billing(_ items: String = #"[{"product":"Copilot","model":"Claude Sonnet 4","grossQuantity":10.0},{"product":"Copilot","model":"GPT-5","grossQuantity":5.0},{"product":"Actions","grossQuantity":99}]"#) -> String {
        #"{"timePeriod":{"year":2025,"month":12},"user":"octocat","usageItems":\#(items)}"#
    }
    nonisolated static let user = #"{"copilot_plan":"business","quota_snapshots":{"premium_interactions":{"entitlement":300,"percent_remaining":99.3,"remaining":298,"unlimited":false}},"quota_reset_date_utc":"2026-03-01T00:00:00.000Z"}"#

    final class Seen: @unchecked Sendable {
        var url: String?
        var authorization: String?
    }

    /// Copilot with its old card's settings where it kept them.
    private func make(mode: String? = nil, body: String? = nil, status: Int = 200, username: String? = "octocat",
                      limit: String? = nil, manual: String? = nil, envVar: String? = nil,
                      vault: MemoryVault = MemoryVault(["copilot.token": "saved"]), environment: [String: String] = [:],
                      ghLogin: String? = nil, refuse: Set<String> = [], seen: Seen = Seen()) throws -> Provider {
        let network = MockNetworkClient()
        let answer = body ?? (mode == "copilotAPI" ? Self.user : Self.billing())
        let userAnswer = mode == "copilotAPI" ? answer : Self.user
        given(network).request(.any).willProduce { @Sendable request in
            seen.url = request.url?.absoluteString
            seen.authorization = request.value(forHTTPHeaderField: "Authorization")
            if let key = seen.authorization, refuse.contains(key) { return (Data(), StubbedProvider.response(401)) }
            if request.url?.path == "/copilot_internal/user" { return (Data(userAnswer.utf8), StubbedProvider.response(status)) }
            return (Data(answer.utf8), StubbedProvider.response(status))
        }
        let settings = InMemoryProviderSettings()
        if let mode { settings.setDataSourceKind(mode, forProvider: "copilot") }
        settings.setValue(username, "username", forProvider: "copilot")
        settings.setValue(limit, "monthlyLimit", forProvider: "copilot")
        settings.setValue(manual, "manualUsage", forProvider: "copilot")
        settings.setValue(envVar, "authEnvVar", forProvider: "copilot")
        let definition = try ProviderFactory.builtIn("copilot")
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "copilot"), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() },
                             security: { arguments in
                                 // The GitHub CLI's login, as go-keyring stores it.
                                 guard arguments.contains("gh:github.com"), let ghLogin else { return (44, "") }
                                 return (0, "go-keyring-base64:" + Data(ghLogin.utf8).base64EncodedString())
                             },
                             scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `should be Copilot, out of the lineup until turned on, with GitHub's Copilot settings as its dashboard`() throws {
        let provider = try make()
        #expect(provider.name == "Copilot")
        #expect(!provider.plainIsInLineup)
        #expect(provider.plainDashboardURL?.absoluteString == "https://github.com/settings/copilot/features")
    }

    // MARK: - Billing API

    @Test func `should show this month's Copilot AI credits against the limit when read from GitHub billing`() async throws {
        let seen = Seen()
        let snapshot = try await make(seen: seen).refreshPlain()
        let quota = try #require(snapshot.quotas.first)
        #expect(snapshot.quotas.count == 1)
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.percentRemaining == 70)
        #expect(quota.resetText == "15/50 AI credits")
        #expect(snapshot.accountEmail == "octocat")
        #expect(seen.url == "https://api.github.com/users/octocat/settings/billing/premium_request/usage")
        #expect(seen.authorization == "Bearer saved")
    }

    @Test func `should reset at the end of the calendar month GitHub bills, in UTC`() async throws {
        let quota = try #require(try await make().refreshPlain().quotas.first)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1767225600)) // 2026-01-01T00:00Z
        #expect(quota.window?.length == TimeInterval(31 * 86400))
    }

    @Test func `should measure the credits against the person's monthly limit`() async throws {
        let quota = try #require(try await make(limit: "300").refreshPlain().quotas.first)
        #expect(quota.resetText == "15/300 AI credits")
        #expect(quota.percentRemaining == 95)
    }

    @Test func `should keep the monthly limit the old card saved as a number`() throws {
        #expect(Setting(id: "monthlyLimit", label: "", kind: .text(pattern: "^[1-9][0-9]*$"), default: "50").value(from: "300") == "300")
    }

    @Test func `should show nothing used yet when GitHub bills no Copilot requests`() async throws {
        let quota = try #require(try await make(body: Self.billing("[]")).refreshPlain().quotas.first)
        #expect(quota.percentRemaining == 100)
        #expect(quota.resetText == "0/50 AI credits")
    }

    @Test(arguments: [("20", 60.0, "20/50 AI credits (manual)"), ("40%", 60.0, "20/50 AI credits (manual)")])
    func `should show the usage the person entered when an organization seat bills nothing`(_ manual: String, _ left: Double, _ text: String) async throws {
        let quota = try #require(try await make(body: Self.billing("[]"), manual: manual).refreshPlain().quotas.first)
        #expect(quota.percentRemaining == left)
        #expect(quota.resetText == text)
    }

    @Test func `should show how far over the limit the usage is`() async throws {
        let quota = try #require(try await make(body: Self.billing("[]"), manual: "198%").refreshPlain().quotas.first)
        #expect(quota.percentRemaining == -98)
    }

    @Test func `should show GitHub's own numbers over the usage the person entered`() async throws {
        let quota = try #require(try await make(manual: "40").refreshPlain().quotas.first)
        #expect(quota.resetText == "15/50 AI credits")
    }

    @Test func `should read the Copilot API when billing has no username`() async throws {
        let seen = Seen()
        _ = try await make(username: nil, seen: seen).refreshPlain()
        #expect(seen.url == "https://api.github.com/copilot_internal/user")
    }

    @Test func `should be unavailable with no username and no token`() async throws {
        #expect(try await make(username: nil, vault: MemoryVault()).isPlainAvailable() == false)
    }

    @Test func `should use the token in the environment variable the person named`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GH", vault: MemoryVault(), environment: ["MY_GH": "env"], seen: seen).refreshPlain()
        #expect(seen.authorization == "Bearer env")
    }

    @Test func `should use COPILOT_TOKEN when the person named no variable`() async throws {
        let seen = Seen()
        _ = try await make(vault: MemoryVault(), environment: ["COPILOT_TOKEN": "env"], seen: seen).refreshPlain()
        #expect(seen.authorization == "Bearer env")
    }

    @Test func `should ask for a new token when GitHub refuses it`() async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(status: 401).refreshPlain() }
    }

    @Test func `should say the token lacks Plan read access when GitHub forbids billing`() async throws {
        await #expect(throws: UsageError.executionFailed("Forbidden - ensure the token has 'Plan: read' permission")) {
            try await make(status: 403).refreshPlain()
        }
    }

    // MARK: - Copilot API

    @Test func `should show the AI credits, plan and monthly reset from the Copilot API when the person chose it`() async throws {
        let seen = Seen()
        let snapshot = try await make(mode: "copilotAPI", seen: seen).refreshPlain()
        #expect(seen.url == "https://api.github.com/copilot_internal/user")
        let quota = try #require(snapshot.quotas.first)
        #expect(quota.percentRemaining == 99.3)
        #expect(quota.resetText == "2/300 AI credits")
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1772323200)) // 2026-03-01T00:00Z
        #expect(quota.window?.length == TimeInterval(28 * 86400))
        // The plan is the account's tier, never its email.
        #expect(snapshot.accountTier == .custom("business"))
        #expect(snapshot.accountEmail == nil)
    }

    @Test func `should show the usage from the Copilot API without a username`() async throws {
        #expect(try await make(mode: "copilotAPI", username: nil).refreshPlain().quotas.count == 1)
    }

    @Test(arguments: [
        #"{"copilot_plan":"enterprise","quota_snapshots":{"premium_interactions":{"unlimited":true}}}"#,
        #"{"copilot_plan":"free","quota_snapshots":{"chat":{"entitlement":50}}}"#,
    ])
    func `should show no made-up 100% when the plan is unlimited or has no AI-credits quota`(_ body: String) async throws {
        let product = try make(mode: "copilotAPI", body: body)
        let account = product.defaultAccount
        let snapshot = try await product.refresh(account)
        #expect(snapshot.quotas.isEmpty)
    }

    @Test func `should read the Copilot API with the GitHub CLI's login when no token is saved`() async throws {
        let seen = Seen()
        let snapshot = try await make(mode: "copilotAPI", vault: MemoryVault(), ghLogin: "gho_cli", seen: seen).refreshPlain()
        #expect(seen.authorization == "Bearer gho_cli")
        #expect(snapshot.quotas.first?.resetText == "2/300 AI credits")
    }

    @Test func `should show the GitHub login and plan the Copilot API names`() async throws {
        let body = #"{"login":"octocat","copilot_plan":"individual","quota_snapshots":{"premium_interactions":{"entitlement":1500,"remaining":1487,"percent_remaining":99.1}}}"#
        let snapshot = try await make(mode: "copilotAPI", body: body).refreshPlain()
        #expect(snapshot.accountEmail == "octocat")
        #expect(snapshot.accountTier == .custom("individual"))
    }

    @Test func `should read the Copilot API with the GitHub CLI's login when billing has no token`() async throws {
        let seen = Seen()
        let snapshot = try await make(vault: MemoryVault(), ghLogin: "gho_cli", seen: seen).refreshPlain()
        #expect(seen.url == "https://api.github.com/copilot_internal/user")
        #expect(snapshot.quotas.first?.resetText == "2/300 AI credits")
    }

    // MARK: - Accounts

    @Test func `should ask an added login on billing for its token, username and monthly limit`() throws {
        #expect(try make().accounts.form.map(\.id) == ["token", "username", "monthlyLimit"])
    }

    @Test func `should ask an added login on the Copilot API only for its token`() throws {
        #expect(try make(mode: "copilotAPI").accounts.form.map(\.id) == ["token"])
    }

    @Test func `should read an added login with its own token, username and limit, never the environment's token`() async throws {
        let seen = Seen()
        let provider = try make(vault: MemoryVault(), environment: ["COPILOT_TOKEN": "env"], seen: seen)
        let work = try provider.accounts.add(filling: ["token": "work", "username": "hubot", "monthlyLimit": "300"])
        let quota = try #require(try await provider.refresh(work).quotas.first)
        #expect(seen.authorization == "Bearer work")
        #expect(seen.url == "https://api.github.com/users/hubot/settings/billing/premium_request/usage")
        #expect(quota.resetText == "15/300 AI credits")
    }
}
