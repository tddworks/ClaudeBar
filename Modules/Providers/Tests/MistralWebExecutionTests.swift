@testable import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Mistral's web source: the Vibe Coding Plan usage chat.mistral.ai knows —
/// a percent used and a reset date inside an NDJSON answer — beside the local
/// Vibe logs. The session is a pasted cookie, `MISTRAL_CHAT_COOKIE`, or the
/// browser's chat.mistral.ai cookies.
@MainActor @Suite
struct MistralWebExecutionTests {
    /// Synthetic NDJSON: one JSON object per line; the usage sits somewhere
    /// inside apiKey.getUsage's result, not on the first line.
    nonisolated static let ndjson = """
    {"json":{"0":[[0],[null,0,0]],"1":[[0],[null,0,1]]}}
    {"json":[3,0,[[{"data":0}],["data",0,4]]]}
    {"json":[6,0,[[{"usagePercentage":12.5,"quotaChangedThisMonth":false,"paygEnabled":false,"resetAt":"2026-11-01T00:00:00Z"}]]]}
    """
    nonisolated static let apiError = """
    {"json":[4,0,[[{"error":"Unauthorized"}]]]}
    """
    nonisolated static let noUsage = """
    {"json":[8,0,[[{"vibeApiKey":"redacted"}]]]}
    """

    final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        func add(_ request: URLRequest) { lock.withLock { stored.append(request) } }
        var requests: [URLRequest] { lock.withLock { stored } }
    }

    private func make(mode: String? = nil, status: Int = 200, vault: MemoryVault = MemoryVault(),
                      cookies: [BrowserCookie] = [], environment: [String: String] = [:], sent: Sent = Sent(),
                      body: String = Self.ndjson) throws -> Provider {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            sent.add(request)
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        let browser = MockBrowserCookieReading()
        given(browser).stores(domains: .any, names: .any).willReturn(cookies.isEmpty ? [] : [cookies])
        let settings = InMemoryProviderSettings()
        if let mode { settings.setDataSourceKind(mode, forProvider: "mistral") }
        let definition = try ProviderFactory.builtIn("mistral")
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "mistral"), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, makeCLIExecutor: { _ in MockCLIExecutor() }, makeCommandExecutor: { _ in MockCLIExecutor() },
                             network: network, makeTransport: { _, _, _, _ in MockRPCTransport() }, security: { _ in (1, "") },
                             scripts: ProviderFactory.builtInScripts, secrets: vault.scoped(to: login), browserCookies: browser,
                             environment: { environment[$0] }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    // MARK: - The definition

    @Test func `should offer the web source beside the Vibe logs, with the logs first`() throws {
        let definition = try ProviderFactory.builtIn("mistral")
        #expect(definition.dataSources.map(\.kind) == ["logs", "web"])
        #expect(definition.defaultDataSource == "logs")
    }

    @Test func `should run an added login's web source on its own pasted cookie only`() throws {
        let definition = try ProviderFactory.builtIn("mistral")
        let sources = try definition.dataSources(forAccount: ["cookie": "ory_session_x=x"])
        let web = try #require(sources.first { $0.kind == "web" })
        let data = String(decoding: (try JSONEncoder().encode(web)), as: UTF8.self)
        #expect(data.contains(#""setting":"cookie""#))
        #expect(!data.contains("browserCookies"))
        #expect(!data.contains("MISTRAL_CHAT_COOKIE"))
    }

    // MARK: - Reading the Vibe plan

    @Test func `should show the Vibe plan's percent and reset when the web source answers`() async throws {
        let sent = Sent()
        let snapshot = try await make(mode: "web", vault: MemoryVault(["mistral.cookie": "ory_session_test=s; csrftoken=c"]), sent: sent).refreshPlain()
        let plan = try #require(snapshot.quota(for: .timeLimit("Vibe plan")))
        #expect(plan.percentRemaining == 87.5)
        #expect(plan.resetsAt == Date(timeIntervalSince1970: 1_793_491_200))
        #expect(plan.resetText == "87% remaining")
        let request = try #require(sent.requests.first)
        #expect(request.url?.host == "chat.mistral.ai")
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/code-trpc/projects.list,apiKey.getApiKey,apiKey.getUsage")
        #expect(request.url?.query?.hasPrefix("batch=1&input=%7B%220%22") == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "trpc-accept") == "application/jsonl")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "ory_session_test=s; csrftoken=c")
    }

    // MARK: - Where the session comes from

    @Test func `should use MISTRAL_CHAT_COOKIE when no cookie is pasted`() async throws {
        let sent = Sent()
        _ = try await make(mode: "web", environment: ["MISTRAL_CHAT_COOKIE": "ory_session_env=e"], sent: sent).refreshPlain()
        #expect(sent.requests.first?.value(forHTTPHeaderField: "Cookie") == "ory_session_env=e")
    }

    @Test func `should send the pasted cookie before the environment's and the browser's`() async throws {
        let sent = Sent()
        let browser = [BrowserCookie(name: "csrftoken", value: "browser")]
        _ = try await make(mode: "web", vault: MemoryVault(["mistral.cookie": "ory_session_pasted=p"]),
                           cookies: browser, environment: ["MISTRAL_CHAT_COOKIE": "ory_session_env=e"], sent: sent).refreshPlain()
        #expect(sent.requests.first?.value(forHTTPHeaderField: "Cookie") == "ory_session_pasted=p")
    }

    @Test func `should read the browser's chat.mistral.ai cookies when there is no pasted or env cookie`() async throws {
        // The engine matches cookie names exactly: of the Ory names the research
        // documents, only `csrftoken` can ever match today — the session cookie's
        // exact name is per-project and unknown (docs/providers/mistral/design.md).
        let sent = Sent()
        let browser = [BrowserCookie(name: "ory_session_mistralai", value: "s"), BrowserCookie(name: "csrftoken", value: "c")]
        _ = try await make(mode: "web", cookies: browser, sent: sent).refreshPlain()
        #expect(sent.requests.first?.value(forHTTPHeaderField: "Cookie") == "csrftoken=c")
    }

    @Test func `should not be available when there is no session anywhere`() async throws {
        #expect(try await make(mode: "web").isPlainAvailable() == false)
    }

    // MARK: - What can go wrong

    @Test(arguments: [401, 403]) func `should ask to sign in again when chat.mistral.ai refuses the cookie`(_ code: Int) async throws {
        await #expect(throws: UsageError.sessionExpired(hint: "Sign in to chat.mistral.ai again, then paste a fresh cookie.")) {
            try await make(mode: "web", status: code, vault: MemoryVault(["mistral.cookie": "ory_session_old=o"])).refreshPlain()
        }
    }

    @Test func `should report the error the answer carries`() async throws {
        await #expect(throws: UsageError.executionFailed("Mistral API error: Unauthorized")) {
            try await make(mode: "web", vault: MemoryVault(["mistral.cookie": "ory_session_old=o"]), body: Self.apiError).refreshPlain()
        }
    }

    @Test func `should say there is no data when the answer carries no usage`() async throws {
        await #expect(throws: UsageError.noData) {
            try await make(mode: "web", vault: MemoryVault(["mistral.cookie": "ory_session_old=o"]), body: Self.noUsage).refreshPlain()
        }
    }

    // MARK: - Added accounts

    @Test func `should ask for a cookie when adding a login on the web`() throws {
        #expect(try make(mode: "web").accounts.form.map(\.id) == ["cookie"])
    }

    @Test func `should use an added login's own cookie, never the browser's`() async throws {
        let sent = Sent()
        let provider = try make(mode: "web", cookies: [BrowserCookie(name: "csrftoken", value: "browser")], sent: sent)
        let work = try provider.accounts.add(filling: ["cookie": "ory_session_work=w"])
        _ = try await provider.refresh(work)
        #expect(sent.requests.last?.value(forHTTPHeaderField: "Cookie") == "ory_session_work=w")
    }
}
