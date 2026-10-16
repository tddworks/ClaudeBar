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
                  request.value(forHTTPHeaderField: "r-timezone") == DataSources.timeZone().identifier else {
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
        let definition = try! ProviderFactory.builtIn("kimi")
        var platform = Platform.current
        platform.runCLI = { @Sendable call in seen.calls.append(call); return cli }
        platform.runCommand = { _ in cli }
        platform.rpcTransport = { _, _, _, _ in MockRPCTransport() }
        platform.keychain = { _ in (1, "") }
        platform.browserCookies = browser
        platform.browserStorage = nil
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: "kimi"), makeDataSource: { [platform] source, login in
            DataSources.make(source, providerId: definition.id, platform: platform, network: network,
                             scripts: ProviderFactory.builtInScripts, secrets: vault.scoped(to: login),
                             environment: { environment[$0] }, homeDirectory: FileManager.default.temporaryDirectory,
                             now: { Date() })
        }, vault: vault)
    }

    // MARK: - CLI, the default

    @Test func `should ask kimi for /usage once its screen settles when no data source is chosen`() async throws {
        let seen = Seen()
        let quotas = try await make(seen: seen).refreshPlain().quotas
        #expect(quotas.map(\.quotaType) == [.weekly, .session])
        #expect(quotas.map(\.percentRemaining) == [10, 88])
        let call = try #require(seen.calls.first)
        #expect(call.input == "/usage")
        #expect(call.inputDelay == 1.5)
        #expect(call.workingDirectory == .dedicated)
        #expect(call.autoResponses["context:"] == "/usage\r")
    }

    @Test func `should read usage from the web when the old card chose the API`() async throws {
        let seen = Seen()
        _ = try await make(mode: "api", cookies: ["kimi.com": "browser"], seen: seen).refreshPlain()
        #expect(seen.host == "www.kimi.com")
        #expect(seen.cookie == "kimi-auth=browser")
    }

    // MARK: - API

    @Test func `should show the Moderato plan's weekly quota and its 5-hour limit when read from the web`() async throws {
        let snapshot = try await make(mode: "api", cookies: ["kimi.com": "browser"]).refreshPlain()
        let weekly = try #require(snapshot.quota(for: .weekly))
        #expect(weekly.window?.length == 604800)
        #expect(weekly.resetText == "214/2048 requests")
        let session = try #require(snapshot.quota(for: .session))
        #expect(session.percentRemaining == 30.5)
        #expect(session.window?.length == 18000)
        #expect(snapshot.accountTier == .custom("Moderato"))
    }

    @Test func `should use kimi.ai and its own browser session when the region is international`() async throws {
        let seen = Seen()
        let provider = make(region: "international", mode: "api", cookies: ["kimi.com": "china", "kimi.ai": "international"], seen: seen)
        _ = try await provider.refreshPlain()
        #expect(seen.host == "www.kimi.ai")
        #expect(seen.origin == "https://www.kimi.ai")
        #expect(seen.cookie == "kimi-auth=international")
        #expect(provider.plainDashboardURL?.absoluteString == "https://www.kimi.ai/code/console")
    }

    @Test func `should use KIMI_AUTH_TOKEN over the browser session when both are set`() async throws {
        let seen = Seen()
        _ = try await make(mode: "api", cookies: ["kimi.com": "browser"], environment: ["KIMI_AUTH_TOKEN": "env"], seen: seen).refreshPlain()
        #expect(seen.cookie == "kimi-auth=env")
    }

    @Test func `should be unavailable when there is no web session anywhere`() async throws {
        let product = make(mode: "api")
        let account = product.defaultAccount
        #expect(await product.isAvailable(account) == false)
    }

    @Test(arguments: [401, 403]) func `should ask to sign in again when Kimi refuses the session`(_ code: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await make(mode: "api", status: code, cookies: ["kimi.com": "browser"]).refreshPlain()
        }
    }

    @Test func `should open the China dashboard when no region is saved`() {
        #expect(make().plainDashboardURL?.absoluteString == "https://www.kimi.com/code/console")
    }

    // MARK: - Added accounts

    @Test func `should ask for a session token and a region when adding a login on the API`() throws {
        #expect(make(mode: "api").accounts.form.map(\.id) == ["token", "region"])
    }

    @Test func `should ask for a signed-in folder and a region when adding a login on the CLI`() throws {
        #expect(make().accounts.form.map(\.id) == ["home", "region"])
    }

    @Test func `should use an added login's own token and region, never the browser, on the API`() async throws {
        let seen = Seen()
        let vault = MemoryVault()
        let provider = make(mode: "api", vault: vault, cookies: ["kimi.com": "browser"], environment: ["KIMI_AUTH_TOKEN": "env"], seen: seen)
        let work = try provider.accounts.add(filling: ["token": "work", "region": "international"])
        _ = try await provider.refresh(work)
        #expect(seen.cookie == "kimi-auth=work")
        #expect(seen.host == "www.kimi.ai")
    }

    @Test func `should run kimi in an added login's own folder on the CLI`() async throws {
        let seen = Seen()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = make(seen: seen)
        let work = try provider.accounts.add(filling: ["home": folder.path])
        _ = try await provider.refresh(work)
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
        try ProviderFactory.builtIn("kimi")
    }

    @Test func `should read only the web when a login has no folder`() throws {
        let sources = try definition().dataSources(forAccount: ["region": "china"])
        #expect(sources.map(\.kind) == ["api"])
    }

    @Test func `should read both the CLI and the web when a login has a folder`() throws {
        let sources = try definition().dataSources(forAccount: ["region": "china", "home": "/tmp/kimi-work"])
        #expect(sources.map(\.kind) == ["cli", "api"])
    }
}
