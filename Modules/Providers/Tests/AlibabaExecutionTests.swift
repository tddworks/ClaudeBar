@testable import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

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
                      browser: [BrowserCookie] = [], page: String = "", sent: Sent = Sent()) throws -> Provider {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            sent.add(request)
            if request.httpMethod == "GET" { return (Data(page.utf8), StubbedProvider.response(200)) }
            return (Data(Self.quota.utf8), StubbedProvider.response(status))
        }
        let cookies = MockBrowserCookieReading()
        given(cookies).stores(domains: .any, names: .any).willReturn(browser.isEmpty ? [] : [browser])
        let settings = InMemoryProviderSettings()
        settings.setValue(region, "region", forProvider: "alibaba")
        if let mode { settings.setDataSourceKind(mode, forProvider: "alibaba") }
        let definition = try Providers.builtIn("alibaba")
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "alibaba"), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, makeCLIExecutor: { _ in MockCLIExecutor() }, makeCommandExecutor: { _ in MockCLIExecutor() },
                             network: network, makeTransport: { _, _, _, _ in MockRPCTransport() }, security: { _ in (1, "") },
                             scripts: Providers.builtInScripts, secrets: vault.scoped(to: login), browserCookies: cookies,
                             environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `definition keeps Alibaba's identity, off until turned on`() throws {
        let provider = try make()
        #expect(provider.name == "Alibaba")
        #expect(!provider.defaultAccount.isEnabled)
        #expect(provider.defaultAccount.dashboardURL?.absoluteString == "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/detail")
    }

    // MARK: - API key

    @Test func `an API key reads the plan from the region's gateway`() async throws {
        let sent = Sent()
        let snapshot = try await make(vault: MemoryVault(["alibaba.apiKey": "sk-1"]), sent: sent).defaultAccount.refresh()
        #expect(snapshot.quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("Monthly")])
        #expect(snapshot.loginMethod == "Pro")
        let request = try #require(sent.last(to: "modelstudio.console.alibabacloud.com"))
        #expect(request.url?.path == "/data/api.json")
        #expect(request.url?.query?.contains("currentRegionId=ap-southeast-1") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        #expect(request.value(forHTTPHeaderField: "X-DashScope-API-Key") == "sk-1")
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("sfm_codingplan_public_intl"))
    }

    @Test func `China Mainland goes to its own gateway, commodity and dashboard`() async throws {
        let sent = Sent()
        let provider = try make(region: "cn", vault: MemoryVault(["alibaba.apiKey": "sk-1"]), sent: sent)
        _ = try await provider.defaultAccount.refresh()
        let request = try #require(sent.last(to: "bailian.console.aliyun.com"))
        #expect(request.url?.query?.contains("currentRegionId=cn-beijing") == true)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("sfm_codingplan_public_cn"))
        #expect(provider.defaultAccount.dashboardURL?.host == "bailian.console.aliyun.com")
    }

    @Test func `the billing month is the month ending on its reset`() async throws {
        let snapshot = try await make(vault: MemoryVault(["alibaba.apiKey": "sk-1"])).defaultAccount.refresh()
        let month = try #require(snapshot.quota(for: .timeLimit("Monthly")))
        #expect(month.window?.length == TimeInterval(28 * 86400))
    }

    // MARK: - Console cookie

    @Test func `with no API key the browser's console session is used`() async throws {
        let sent = Sent()
        let browser = [BrowserCookie(name: "login_aliyunid_ticket", value: "t"), BrowserCookie(name: "login_aliyunid_csrf", value: "c-1"),
                       BrowserCookie(name: "sec_token", value: "s-1")]
        let snapshot = try await make(browser: browser, sent: sent).defaultAccount.refresh()
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

    @Test func `a cookie without sec_token takes it from the console page`() async throws {
        let sent = Sent()
        let provider = try make(mode: "cookie", vault: MemoryVault(["alibaba.cookie": "login_aliyunid_ticket=t"]),
                                page: #"<script>window.ALIYUN = {"sec_token": "page-9"}</script>"#, sent: sent)
        _ = try await provider.defaultAccount.refresh()
        let page = try #require(sent.requests.first { $0.httpMethod == "GET" })
        #expect(page.value(forHTTPHeaderField: "Cookie") == "login_aliyunid_ticket=t")
        let request = try #require(sent.last(to: "bailian-singapore-cs.alibabacloud.com"))
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self).hasSuffix("&sec_token=page-9"))
        // No CSRF cookie: no x-csrf-token header rather than a failure.
        #expect(request.value(forHTTPHeaderField: "x-csrf-token") == nil)
    }

    @Test func `a pasted cookie comes before the browser's`() async throws {
        let sent = Sent()
        _ = try await make(mode: "cookie", vault: MemoryVault(["alibaba.cookie": "sec_token=pasted"]),
                           browser: [BrowserCookie(name: "sec_token", value: "browser")], sent: sent).defaultAccount.refresh()
        #expect(sent.last(to: "bailian-singapore-cs.alibabacloud.com")?.value(forHTTPHeaderField: "Cookie") == "sec_token=pasted")
    }

    @Test func `a refused console session asks to sign in again`() async throws {
        await #expect(throws: UsageError.sessionExpired(hint: "Re-authenticate in Alibaba Cloud console.")) {
            try await make(mode: "cookie", status: 401, vault: MemoryVault(["alibaba.cookie": "sec_token=s"])).defaultAccount.refresh()
        }
    }

    @Test func `nothing anywhere is not ready`() async throws {
        #expect(await (try make()).defaultAccount.isAvailable() == false)
    }

    // MARK: - Accounts

    @Test func `an added account asks for what the active data source uses`() throws {
        #expect(try make().accountForm.map(\.id) == ["apiKey", "region"])
        #expect(try make(mode: "cookie").accountForm.map(\.id) == ["cookie", "region"])
    }

    @Test func `an added cookie account uses its own cookie, never the browser's`() async throws {
        let sent = Sent()
        let provider = try make(mode: "cookie", browser: [BrowserCookie(name: "sec_token", value: "browser")], sent: sent)
        let work = try provider.addAccount(filling: ["cookie": "sec_token=work", "region": "cn"])
        _ = try await work.refresh()
        let request = try #require(sent.last(to: "bailian-beijing-cs.aliyuncs.com"))
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sec_token=work")
    }
}
