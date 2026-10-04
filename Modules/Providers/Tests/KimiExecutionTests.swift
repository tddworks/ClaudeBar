import Foundation
import Mockable
import Providers
@testable import DataSources
import Quotas
import Testing

/// Kimi on stubbed connections: the CLI types /usage into `kimi`; the API
/// reads the web session for the chosen region. An added login brings what
/// the active data source needs — a session token, or a signed-in folder.
@MainActor @Suite
struct KimiExecutionTests {
    nonisolated static let api = #"{"usages":[{"scope":"FEATURE_CODING","detail":{"limit":"2048","used":"214","remaining":"1834","resetTime":"2025-06-09T00:00:00Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"139","remaining":"61","resetTime":"2025-06-03T15:30:00Z"}}]}]}"#
    nonisolated static let screen = """
      ╭ Usage ───────────────────────────────────────────────────────────╮
      │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
      │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
      ╰──────────────────────────────────────────────────────────────────╯
    """

    final class Seen: @unchecked Sendable {
        var host: String?
        var cookie: String?
        var origin: String?
        var calls: [CLICall] = []
    }

    /// Kimi with its old card's settings where it kept them: `kimi.region`
    /// and `kimi.probeMode`.
    private func make(region: String? = nil, mode: String? = nil, status: Int = 200, vault: MemoryVault = MemoryVault(),
                      cookies: [String: String] = [:], environment: [String: String] = [:], seen: Seen = Seen()) -> Provider {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.host = request.url?.host
            seen.cookie = request.value(forHTTPHeaderField: "Cookie")
            seen.origin = request.value(forHTTPHeaderField: "Origin")
            guard request.httpMethod == "POST", request.url?.path == "/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages",
                  request.httpBody == Data(#"{"scope":["FEATURE_CODING"]}"#.utf8),
                  request.value(forHTTPHeaderField: "r-timezone") == TimeZone.current.identifier else {
                return (Data(), StubbedProvider.response(400))
            }
            return (Data(Self.api.utf8), StubbedProvider.response(status))
        }
        let browser = MockBrowserCookieReading()
        given(browser).stores(domains: .any, names: .value(["kimi-auth"])).willProduce { @Sendable domains, _ in
            domains.compactMap { cookies[$0] }.map { [BrowserCookie(name: "kimi-auth", value: $0)] }
        }
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn("/opt/homebrew/bin/kimi")
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: Self.screen))
        let settings = InMemoryProviderSettings()
        settings.setValue(region, "region", forProvider: "kimi")
        if let mode { settings.setDataSourceKind(mode, forProvider: "kimi") }
        let definition = try! Providers.builtIn("kimi")
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "kimi"), makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, makeCLIExecutor: { @Sendable call in seen.calls.append(call); return cli },
                             makeCommandExecutor: { _ in cli }, network: network, makeTransport: { _, _, _, _ in MockRPCTransport() },
                             security: { _ in (1, "") }, scripts: Providers.builtInScripts, secrets: vault.scoped(to: login),
                             browserCookies: browser, environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    // MARK: - CLI, the default

    @Test func `the CLI is the default and types /usage once the screen settles`() async throws {
        let seen = Seen()
        let quotas = try await make(seen: seen).defaultAccount.refresh().quotas
        #expect(quotas.map(\.quotaType) == [.weekly, .session])
        #expect(quotas.map(\.percentRemaining) == [10, 88])
        let call = try #require(seen.calls.first)
        #expect(call.input == "/usage")
        #expect(call.inputDelay == 1.5)
        #expect(call.workingDirectory == .dedicated)
        #expect(call.autoResponses["context:"] == "/usage\r")
    }

    @Test func `the old card's API choice is read`() async throws {
        let seen = Seen()
        _ = try await make(mode: "api", cookies: ["kimi.com": "browser"], seen: seen).defaultAccount.refresh()
        #expect(seen.host == "www.kimi.com")
        #expect(seen.cookie == "kimi-auth=browser")
    }

    // MARK: - API

    @Test func `the API reads the plan and its 5-hour limit`() async throws {
        let snapshot = try await make(mode: "api", cookies: ["kimi.com": "browser"]).defaultAccount.refresh()
        let weekly = try #require(snapshot.quota(for: .weekly))
        #expect(weekly.window?.length == 604800)
        #expect(weekly.resetText == "214/2048 requests")
        let session = try #require(snapshot.quota(for: .session))
        #expect(session.percentRemaining == 30.5)
        #expect(session.window?.length == 18000)
        #expect(snapshot.accountTier == .custom("Moderato"))
    }

    @Test func `the international region goes to kimi.ai with its own cookie`() async throws {
        let seen = Seen()
        let provider = make(region: "international", mode: "api", cookies: ["kimi.com": "china", "kimi.ai": "international"], seen: seen)
        _ = try await provider.defaultAccount.refresh()
        #expect(seen.host == "www.kimi.ai")
        #expect(seen.origin == "https://www.kimi.ai")
        #expect(seen.cookie == "kimi-auth=international")
        #expect(provider.defaultAccount.dashboardURL?.absoluteString == "https://www.kimi.ai/code/console")
    }

    @Test func `KIMI_AUTH_TOKEN comes before the browser`() async throws {
        let seen = Seen()
        _ = try await make(mode: "api", cookies: ["kimi.com": "browser"], environment: ["KIMI_AUTH_TOKEN": "env"], seen: seen).defaultAccount.refresh()
        #expect(seen.cookie == "kimi-auth=env")
    }

    @Test func `no session anywhere is not ready`() async throws {
        let account = make(mode: "api").defaultAccount
        #expect(await account.isAvailable() == false)
    }

    @Test(arguments: [401, 403]) func `a refused session needs signing in again`(_ code: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await make(mode: "api", status: code, cookies: ["kimi.com": "browser"]).defaultAccount.refresh()
        }
    }

    @Test func `China is the dashboard with no region saved`() {
        #expect(make().defaultAccount.dashboardURL?.absoluteString == "https://www.kimi.com/code/console")
    }

    // MARK: - Added accounts

    @Test func `on the API an added account asks for a session token and a region`() throws {
        #expect(make(mode: "api").accountForm.map(\.id) == ["token", "region"])
    }

    @Test func `on the CLI an added account asks for a signed-in folder and a region`() throws {
        #expect(make().accountForm.map(\.id) == ["home", "region"])
    }

    @Test func `an added API account uses its own token and region, never the browser`() async throws {
        let seen = Seen()
        let vault = MemoryVault()
        let provider = make(mode: "api", vault: vault, cookies: ["kimi.com": "browser"], environment: ["KIMI_AUTH_TOKEN": "env"], seen: seen)
        let work = try provider.addAccount(filling: ["token": "work", "region": "international"])
        _ = try await work.refresh()
        #expect(seen.cookie == "kimi-auth=work")
        #expect(seen.host == "www.kimi.ai")
    }

    @Test func `an added CLI account runs kimi with its own folder`() async throws {
        let seen = Seen()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = try make(seen: seen).addAccount(filling: ["home": folder.path])
        _ = try await work.refresh()
        let call = try #require(seen.calls.last)
        #expect(call.environment.set["KIMI_SHARE_DIR"] == folder.path)
        #expect(call.environment.set["KIMI_CODE_HOME"] == folder.path)
        #expect(call.environment.unset.contains("KIMI_AUTH_TOKEN"))
    }
}

/// A login added for one data source runs only the sources it has values for.
@Suite
struct SourceScopedAccountTests {
    private func definition() throws -> ProviderDefinition {
        try Providers.builtIn("kimi")
    }

    @Test func `a login without a folder runs no CLI, only the API`() throws {
        let sources = try definition().dataSources(forAccount: ["region": "china"])
        #expect(sources.map(\.kind) == ["api"])
    }

    @Test func `a login with a folder runs both`() throws {
        let sources = try definition().dataSources(forAccount: ["region": "china", "home": "/tmp/kimi-work"])
        #expect(sources.map(\.kind) == ["cli", "api"])
    }
}
