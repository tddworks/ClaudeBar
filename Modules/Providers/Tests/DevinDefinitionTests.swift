import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Devin as data: the organization's daily and weekly quota from
/// `app.devin.ai`, with the browser's sign-in, or a pasted session token and
/// organization ID, read by `devin-quota.js`.
@MainActor @Suite
struct DevinDefinitionTests {
    static let quota = #"{"is_quota_plan":true,"has_quota_allocation":true,"daily_percentage":0.12,"weekly_percentage":42,"daily_reset_at":"2026-06-11T00:00:00-08:00","weekly_reset_at":"2026-06-14T00:00:00-08:00","hide_daily_quota":false}"#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?

        func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            self.request = request
        }

        var last: URLRequest? {
            lock.lock(); defer { lock.unlock() }
            return request
        }
    }

    private func make(body: String = Self.quota, status: Int = 200, environment: [String: String] = [:],
                      vault: MemoryVault = MemoryVault(["devin.token": "auth1_pasted-session-token"]),
                      settings: InMemoryProviderSettings = DevinDefinitionTests.organization("org_abc123"),
                      browser: [[String: String]] = [], seen: Seen = Seen()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("devin")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.record(request)
            guard request.httpMethod == "GET", request.value(forHTTPHeaderField: "Accept") == "application/json" else {
                return (Data(), StubbedProvider.response(400))
            }
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        let storage = MockBrowserStorageReading()
        given(storage).stores(origin: .any).willReturn(browser)
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: definition.id),
                        makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), browserStorage: storage, environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    static func organization(_ id: String) -> InMemoryProviderSettings {
        let settings = InMemoryProviderSettings()
        settings.setValue(id, "organization", forProvider: "devin")
        return settings
    }

    @Test
    func `should be Devin, off until turned on, with its dashboard and icon`() throws {
        let devin = try make()
        #expect(devin.id == "devin")
        #expect(devin.name == "Devin")
        #expect(devin.plainIsInLineup == false)
        #expect(devin.definition.profile.links.dashboard == URL(string: "https://app.devin.ai/settings/usage"))
        #expect(devin.definition.profile.look.icon == "DevinIcon")
    }

    @Test
    func `should ask for the organization's quota with the pasted token`() async throws {
        let seen = Seen()
        _ = try await make(seen: seen).refreshPlain()
        let request = try #require(seen.last)
        #expect(request.url?.absoluteString == "https://app.devin.ai/api/org_abc123/billing/quota/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer auth1_pasted-session-token")
        #expect(request.value(forHTTPHeaderField: "x-cog-org-id") == "org_abc123")
    }

    @Test
    func `should show the daily and weekly quota, reading a fraction as a percentage`() async throws {
        let usage = try await make().refreshPlain()
        let daily = try #require(usage.quotas.first { $0.quotaType == .timeLimit("Daily") })
        #expect(abs(daily.percentRemaining - 88) < 0.0001)
        #expect(daily.resetsAt == ISO8601DateFormatter().date(from: "2026-06-11T08:00:00Z"))
        let weekly = try #require(usage.quota(for: .weekly))
        #expect(weekly.percentRemaining == 58)
        #expect(weekly.resetsAt == ISO8601DateFormatter().date(from: "2026-06-14T08:00:00Z"))
    }

    @Test
    func `should leave out the daily quota when Devin hides it`() async throws {
        let body = #"{"daily_percentage":10,"weekly_percentage":42,"hide_daily_quota":true}"#
        let usage = try await make(body: body).refreshPlain()
        #expect(usage.quotas.map(\.quotaType) == [.weekly])
    }

    @Test
    func `should read the nested quota answer, its plan and the extra usage balance`() async throws {
        let body = #"{"plan_name":"pro","overage_balance":70.87,"quota_usage":{"daily_quota":{"used":3,"limit":10,"reset_at":"2026-06-01T08:00:00Z"},"weekly_quota":{"remaining_percent":0.25,"next_reset_at":1780560000}}}"#
        let usage = try await make(body: body).refreshPlain()
        #expect(usage.quotas.first { $0.quotaType == .timeLimit("Daily") }?.percentRemaining == 70)
        #expect(usage.quota(for: .weekly)?.percentRemaining == 25)
        #expect(usage.quota(for: .weekly)?.resetsAt == Date(timeIntervalSince1970: 1780560000))
        #expect(usage.accountTier == .custom("Pro"))
        let extra = try #require(usage.quotas.first { $0.quotaType == .modelSpecific("Extra usage") })
        #expect(extra.left == .money(Money(Decimal(string: "70.87")!, currency: "USD"), of: nil))
    }

    @Test
    func `should use the token from the environment before the pasted one`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["DEVIN_BEARER_TOKEN": "auth1_environment"], seen: seen).refreshPlain()
        #expect(seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer auth1_environment")
    }

    @Test
    func `should ask for a token when there is none`() async throws {
        let devin = try make(vault: MemoryVault())
        let account = devin.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await devin.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test(arguments: [401, 403])
    func `should ask for a new token when Devin refuses it`(_ status: Int) async throws {
        let devin = try make(status: status)
        await #expect(throws: UsageError.sessionExpired(hint: "Sign in to app.devin.ai again, or paste a new session token.")) {
            try await devin.refresh(devin.defaultAccount)
        }
    }

    @Test
    func `should fail reading the quota when Devin's answer has no daily or weekly window`() async throws {
        let devin = try make(body: #"{"is_quota_plan":false}"#)
        let account = devin.defaultAccount
        await #expect(throws: UsageError.self) { try await devin.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }

    // MARK: - The browser's sign-in

    private static let signedIn = ["persist:auth1_session": #"{"token":"auth1_browser"}"#,
                                   "last-internal-org-for-external-org-v1-acme": #""org_browser""#]

    @Test
    func `should use the app.devin.ai sign-in in the browser before anything pasted`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["DEVIN_BEARER_TOKEN": "auth1_environment"], browser: [Self.signedIn], seen: seen).refreshPlain()
        let request = try #require(seen.last)
        #expect(request.url?.absoluteString == "https://app.devin.ai/api/org_browser/billing/quota/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer auth1_browser")
        #expect(request.value(forHTTPHeaderField: "x-cog-org-id") == "org_browser")
    }

    @Test
    func `should use the pasted token with the pasted organization when the browser has no sign-in`() async throws {
        let seen = Seen()
        _ = try await make(browser: [["unrelated": "x"]], seen: seen).refreshPlain()
        #expect(seen.last?.url?.absoluteString == "https://app.devin.ai/api/org_abc123/billing/quota/usage")
        #expect(seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer auth1_pasted-session-token")
    }

    @Test
    func `should list the browser first in the key lookup order`() throws {
        let devin = try make()
        let lookup = try #require(devin.definition.dataSources.first?.credential)
        #expect(lookup.lookupOrder == ["Browser storage · app.devin.ai", "$DEVIN_BEARER_TOKEN", "API key saved in ClaudeBar"])
    }

    @Test
    func `should read an added login only with its own pasted token, never the browser's`() async throws {
        let settings = Self.organization("org_abc123")
        let vault = MemoryVault(["devin.token": "auth1_pasted-session-token"])
        let seen = Seen()
        let devin = try make(vault: vault, settings: settings, browser: [Self.signedIn], seen: seen)
        let work = try devin.accounts.add(filling: ["token": "auth1_work", "organization": "org_work"])
        _ = try await devin.refresh(work)
        #expect(seen.last?.url?.absoluteString == "https://app.devin.ai/api/org_work/billing/quota/usage")
        #expect(seen.last?.value(forHTTPHeaderField: "Authorization") == "Bearer auth1_work")
    }
}
