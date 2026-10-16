@testable import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Alibaba on stubbed connections: an API key, or the console session — a
/// pasted cookie or the browser's — whose `sec_token` comes from the cookie
/// or, failing that, from the console page.
@MainActor @Suite
struct AlibabaExecutionTests {
    nonisolated static let quota = #"{"data":{"codingPlanInstanceInfos":[{"status":"VALID","planName":"Pro","codingPlanQuotaInfo":{"per5HourUsedQuota":10,"per5HourTotalQuota":100,"perWeekUsedQuota":25,"perWeekTotalQuota":500,"perBillMonthUsedQuota":50,"perBillMonthTotalQuota":2000,"perBillMonthQuotaNextRefreshTime":"2026-03-01T00:00:00Z"}}]}}"#

    final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        func add(_ request: URLRequest) { lock.withLock { stored.append(request) } }
        var requests: [URLRequest] { lock.withLock { stored } }
        func last(to host: String) -> URLRequest? { requests.last { $0.url?.host == host } }
    }

    /// Alibaba with its old card's settings where it kept them.
    private func make(region: String? = nil, mode: String? = nil, status: Int = 200, vault: MemoryVault = MemoryVault(),
                      browser: [BrowserCookie] = [], page: String = "", sent: Sent = Sent(), quota: String = Self.quota) throws -> Provider {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            sent.add(request)
            if request.httpMethod == "GET" { return (Data(page.utf8), StubbedProvider.response(200)) }
            return (Data(quota.utf8), StubbedProvider.response(status))
        }
        let cookies = MockBrowserCookieReading()
        given(cookies).stores(domains: .any, names: .any).willReturn(browser.isEmpty ? [] : [browser])
        let settings = InMemoryProviderSettings()
        settings.setValue(region, "region", forProvider: "alibaba")
        if let mode { settings.setDataSourceKind(mode, forProvider: "alibaba") }
        let definition = try ProviderFactory.builtIn("alibaba")
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "alibaba"), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(),
                             network: network, makeTransport: { _, _, _, _ in MockRPCTransport() }, security: { _ in (1, "") },
                             scripts: ProviderFactory.builtInScripts, secrets: vault.scoped(to: login), browserCookies: cookies,
                             environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `should keep Alibaba's name and dashboard, off until the person turns it on`() throws {
        let provider = try make()
        #expect(provider.name == "Alibaba")
        #expect(!provider.plainIsInLineup)
        #expect(provider.plainDashboardURL?.absoluteString == "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/detail")
    }

    // MARK: - API key

    @Test func `should show the plan from the region's gateway when the person has an API key`() async throws {
        let sent = Sent()
        let snapshot = try await make(vault: MemoryVault(["alibaba.apiKey": "sk-1"]), sent: sent).refreshPlain()
        #expect(snapshot.quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("Monthly")])
        #expect(snapshot.loginMethod == "Pro")
        let request = try #require(sent.last(to: "modelstudio.console.alibabacloud.com"))
        #expect(request.url?.path == "/data/api.json")
        #expect(request.url?.query?.contains("currentRegionId=ap-southeast-1") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        #expect(request.value(forHTTPHeaderField: "X-DashScope-API-Key") == "sk-1")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("sfm_codingplan_public_intl"))
    }

    @Test func `should ask China Mainland's own gateway, commodity and dashboard when that region is chosen`() async throws {
        let sent = Sent()
        let provider = try make(region: "cn", vault: MemoryVault(["alibaba.apiKey": "sk-1"]), sent: sent)
        _ = try await provider.refreshPlain()
        let request = try #require(sent.last(to: "bailian.console.aliyun.com"))
        #expect(request.url?.query?.contains("currentRegionId=cn-beijing") == true)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("sfm_codingplan_public_cn"))
        #expect(provider.plainDashboardURL?.host == "bailian.console.aliyun.com")
    }

    @Test func `should give the billing month the length of the month ending on its reset`() async throws {
        let snapshot = try await make(vault: MemoryVault(["alibaba.apiKey": "sk-1"])).refreshPlain()
        let month = try #require(snapshot.quota(for: .timeLimit("Monthly")))
        #expect(month.window?.length == TimeInterval(28 * 86400))
    }

    @Test(arguments: [("2024-03-01T00:00:00Z", 29), ("2026-03-31T00:00:00Z", 31), ("2026-01-31T00:00:00Z", 31)])
    func `should measure billing months in UTC and clamp the previous month end`(_ fixture: (String, Int)) async throws {
        let quota = Self.quota.replacingOccurrences(of: "2026-03-01T00:00:00Z", with: fixture.0)
        let snapshot = try await make(vault: MemoryVault(["alibaba.apiKey": "fake"]), quota: quota).refreshPlain()
        #expect(snapshot.quota(for: .timeLimit("Monthly"))?.window?.length == TimeInterval(fixture.1 * 86400))
    }

    // MARK: - Console cookie

    @Test func `should use the browser's console session when there is no API key`() async throws {
        let sent = Sent()
        let browser = [BrowserCookie(name: "login_aliyunid_ticket", value: "t"), BrowserCookie(name: "login_aliyunid_csrf", value: "c-1"),
                       BrowserCookie(name: "sec_token", value: "s-1")]
        let snapshot = try await make(browser: browser, sent: sent).refreshPlain()
        #expect(snapshot.quotas.count == 3)
        // The cookie held sec_token: the console page isn't asked.
        #expect(sent.requests.allSatisfy { $0.httpMethod == "POST" })
        let request = try #require(sent.last(to: "bailian-singapore-cs.alibabacloud.com"))
        #expect(request.url?.query?.contains("action=IntlBroadScopeAspnGateway") == true)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "login_aliyunid_ticket=t; login_aliyunid_csrf=c-1; sec_token=s-1")
        #expect(request.value(forHTTPHeaderField: "x-csrf-token") == "c-1")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.hasSuffix("&region=ap-southeast-1&sec_token=s-1"))
        #expect(body.removingPercentEncoding?.contains(#""commodityCode":"sfm_codingplan_public_intl""#) == true)
    }

    @Test func `should take the console token from the console page when the pasted cookie has none`() async throws {
        let sent = Sent()
        let provider = try make(mode: "cookie", vault: MemoryVault(["alibaba.cookie": "login_aliyunid_ticket=t"]),
                                page: #"<script>window.ALIYUN = {"sec_token": "page-9"}</script>"#, sent: sent)
        _ = try await provider.refreshPlain()
        let page = try #require(sent.requests.first { $0.httpMethod == "GET" })
        #expect(page.value(forHTTPHeaderField: "Cookie") == "login_aliyunid_ticket=t")
        let request = try #require(sent.last(to: "bailian-singapore-cs.alibabacloud.com"))
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).hasSuffix("&sec_token=page-9"))
        // No CSRF cookie: no x-csrf-token header rather than a failure.
        #expect(request.value(forHTTPHeaderField: "x-csrf-token") == nil)
    }

    @Test func `should send the pasted cookie before the browser's`() async throws {
        let sent = Sent()
        _ = try await make(mode: "cookie", vault: MemoryVault(["alibaba.cookie": "sec_token=pasted"]),
                           browser: [BrowserCookie(name: "sec_token", value: "browser")], sent: sent).refreshPlain()
        #expect(sent.last(to: "bailian-singapore-cs.alibabacloud.com")?.value(forHTTPHeaderField: "Cookie") == "sec_token=pasted")
    }

    @Test func `should ask to sign in again when the console session is refused`() async throws {
        await #expect(throws: UsageError.sessionExpired(hint: "Re-authenticate in Alibaba Cloud console.")) {
            try await make(mode: "cookie", status: 401, vault: MemoryVault(["alibaba.cookie": "sec_token=s"])).refreshPlain()
        }
    }

    @Test func `should not be available when there is no key and no cookie anywhere`() async throws {
        #expect(try await make().isPlainAvailable() == false)
    }

    // MARK: - Accounts

    @Test func `should ask an added account for what the chosen data source uses`() throws {
        #expect(try make().accounts.form.map(\.id) == ["apiKey", "region"])
        #expect(try make(mode: "cookie").accounts.form.map(\.id) == ["cookie", "region"])
    }

    @Test func `should use an added cookie account's own cookie, never the browser's`() async throws {
        let sent = Sent()
        let provider = try make(mode: "cookie", browser: [BrowserCookie(name: "sec_token", value: "browser")], sent: sent)
        let work = try provider.accounts.add(filling: ["cookie": "sec_token=work", "region": "cn"])
        _ = try await provider.refresh(work)
        let request = try #require(sent.last(to: "bailian-beijing-cs.aliyuncs.com"))
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sec_token=work")
    }
}
