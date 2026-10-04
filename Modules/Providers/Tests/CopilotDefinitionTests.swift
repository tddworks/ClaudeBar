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
        let definition = try Providers.builtIn("copilot")
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "copilot"), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() },
                             security: { arguments in
                                 // The GitHub CLI's login, as go-keyring stores it.
                                 guard arguments.contains("gh:github.com"), let ghLogin else { return (44, "") }
                                 return (0, "go-keyring-base64:" + Data(ghLogin.utf8).base64EncodedString())
                             },
                             scripts: Providers.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `definition keeps Copilot's identity, off until turned on`() throws {
        let provider = try make()
        #expect(provider.name == "Copilot")
        #expect(!provider.defaultAccount.isEnabled)
        #expect(provider.defaultAccount.dashboardURL?.absoluteString == "https://github.com/settings/copilot/features")
    }

    // MARK: - Billing API

    @Test func `billing sums this month's Copilot requests against the limit`() async throws {
        let seen = Seen()
        let snapshot = try await make(seen: seen).defaultAccount.refresh()
        let quota = try #require(snapshot.quotas.first)
        #expect(snapshot.quotas.count == 1)
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.percentRemaining == 70)
        #expect(quota.resetText == "15/50 AI credits")
        #expect(snapshot.accountEmail == "octocat")
        #expect(seen.url == "https://api.github.com/users/octocat/settings/billing/premium_request/usage")
        #expect(seen.authorization == "Bearer saved")
    }

    @Test func `the billing month is the calendar month GitHub names, in UTC`() async throws {
        let quota = try #require(try await make().defaultAccount.refresh().quotas.first)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1767225600)) // 2026-01-01T00:00Z
        #expect(quota.window?.length == TimeInterval(31 * 86400))
    }

    @Test func `the person's monthly limit is used`() async throws {
        let quota = try #require(try await make(limit: "300").defaultAccount.refresh().quotas.first)
        #expect(quota.resetText == "15/300 AI credits")
        #expect(quota.percentRemaining == 95)
    }

    @Test func `the old card's monthly limit, saved as a number, reads as the setting`() throws {
        #expect(Setting(id: "monthlyLimit", label: "", kind: .text(pattern: "^[1-9][0-9]*$"), default: "50").value(from: "300") == "300")
    }

    @Test func `no Copilot items is nothing used yet`() async throws {
        let quota = try #require(try await make(body: Self.billing("[]")).defaultAccount.refresh().quotas.first)
        #expect(quota.percentRemaining == 100)
        #expect(quota.resetText == "0/50 AI credits")
    }

    @Test(arguments: [("20", 60.0, "20/50 AI credits (manual)"), ("40%", 60.0, "20/50 AI credits (manual)")])
    func `an organization seat shows the usage the person entered`(_ manual: String, _ left: Double, _ text: String) async throws {
        let quota = try #require(try await make(body: Self.billing("[]"), manual: manual).defaultAccount.refresh().quotas.first)
        #expect(quota.percentRemaining == left)
        #expect(quota.resetText == text)
    }

    @Test func `over the limit shows how far over`() async throws {
        let quota = try #require(try await make(body: Self.billing("[]"), manual: "198%").defaultAccount.refresh().quotas.first)
        #expect(quota.percentRemaining == -98)
    }

    @Test func `GitHub's own numbers win over an entered usage`() async throws {
        let quota = try #require(try await make(manual: "40").defaultAccount.refresh().quotas.first)
        #expect(quota.resetText == "15/50 AI credits")
    }

    @Test func `billing without a username hands over to the Copilot API`() async throws {
        let seen = Seen()
        _ = try await make(username: nil, seen: seen).defaultAccount.refresh()
        #expect(seen.url == "https://api.github.com/copilot_internal/user")
    }

    @Test func `nothing anywhere is not ready`() async throws {
        #expect(await (try make(username: nil, vault: MemoryVault())).defaultAccount.isAvailable() == false)
    }

    @Test func `the token is read from the environment variable the person named`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GH", vault: MemoryVault(), environment: ["MY_GH": "env"], seen: seen).defaultAccount.refresh()
        #expect(seen.authorization == "Bearer env")
    }

    @Test func `COPILOT_TOKEN is read when no variable is named`() async throws {
        let seen = Seen()
        _ = try await make(vault: MemoryVault(), environment: ["COPILOT_TOKEN": "env"], seen: seen).defaultAccount.refresh()
        #expect(seen.authorization == "Bearer env")
    }

    @Test func `a refused token needs a new one`() async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(status: 401).defaultAccount.refresh() }
    }

    @Test func `a token without billing access says what it lacks`() async throws {
        await #expect(throws: UsageError.executionFailed("Forbidden - ensure the token has 'Plan: read' permission")) {
            try await make(status: 403).defaultAccount.refresh()
        }
    }

    // MARK: - Copilot API

    @Test func `the old card's Copilot API choice is read`() async throws {
        let seen = Seen()
        let snapshot = try await make(mode: "copilotAPI", seen: seen).defaultAccount.refresh()
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

    @Test func `the Copilot API needs no username`() async throws {
        #expect(try await make(mode: "copilotAPI", username: nil).defaultAccount.refresh().quotas.count == 1)
    }

    @Test(arguments: [
        #"{"copilot_plan":"enterprise","quota_snapshots":{"premium_interactions":{"unlimited":true}}}"#,
        #"{"copilot_plan":"free","quota_snapshots":{"chat":{"entitlement":50}}}"#,
    ])
    func `unlimited or no AI-credits quota shows the plan, never a made-up 100%`(_ body: String) async throws {
        let account = try make(mode: "copilotAPI", body: body).defaultAccount
        let snapshot = try? await account.refresh()
        #expect(snapshot?.quotas.isEmpty ?? true)
    }

    @Test func `with no token saved, the GitHub CLI's login reads the Copilot API`() async throws {
        let seen = Seen()
        let snapshot = try await make(mode: "copilotAPI", vault: MemoryVault(), ghLogin: "gho_cli", seen: seen).defaultAccount.refresh()
        #expect(seen.authorization == "Bearer gho_cli")
        #expect(snapshot.quotas.first?.resetText == "2/300 AI credits")
    }

    @Test func `the Copilot API names the login it read`() async throws {
        let body = #"{"login":"octocat","copilot_plan":"individual","quota_snapshots":{"premium_interactions":{"entitlement":1500,"remaining":1487,"percent_remaining":99.1}}}"#
        let snapshot = try await make(mode: "copilotAPI", body: body).defaultAccount.refresh()
        #expect(snapshot.accountEmail == "octocat")
        #expect(snapshot.accountTier == .custom("individual"))
    }

    @Test func `billing with no key hands over to the Copilot API and the GitHub CLI's login`() async throws {
        let seen = Seen()
        let snapshot = try await make(vault: MemoryVault(), ghLogin: "gho_cli", seen: seen).defaultAccount.refresh()
        #expect(seen.url == "https://api.github.com/copilot_internal/user")
        #expect(snapshot.quotas.first?.resetText == "2/300 AI credits")
    }

    // MARK: - Accounts

    @Test func `on billing an added account asks for its token, username and limit`() throws {
        #expect(try make().accountForm.map(\.id) == ["token", "username", "monthlyLimit"])
    }

    @Test func `on the Copilot API an added account asks only for its token`() throws {
        #expect(try make(mode: "copilotAPI").accountForm.map(\.id) == ["token"])
    }

    @Test func `an added account uses its own token and username, never the environment`() async throws {
        let seen = Seen()
        let provider = try make(vault: MemoryVault(), environment: ["COPILOT_TOKEN": "env"], seen: seen)
        let work = try provider.addAccount(filling: ["token": "work", "username": "hubot", "monthlyLimit": "300"])
        let quota = try #require(try await work.refresh().quotas.first)
        #expect(seen.authorization == "Bearer work")
        #expect(seen.url == "https://api.github.com/users/hubot/settings/billing/premium_request/usage")
        #expect(quota.resetText == "15/300 AI credits")
    }
}
