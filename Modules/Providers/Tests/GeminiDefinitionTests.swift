import Foundation
import Mockable
import Providers
@testable import DataSources
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Gemini as data: the Gemini CLI's login file, Code Assist's project, then
/// its per-model quota — the old probe's fixtures, quota for quota. A refused
/// token runs `gemini` once to renew its own login.
@MainActor @Suite
struct GeminiDefinitionTests {
    nonisolated static let tiers = #"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.88,"resetTime":"2026-05-10T17:28:41Z"},{"modelId":"gemini-3-pro-preview","remainingFraction":0.88,"resetTime":"2026-05-10T17:28:41Z"},{"modelId":"gemini-3.1-pro-preview","remainingFraction":0.88,"resetTime":"2026-05-10T17:28:41Z"},{"modelId":"gemini-2.5-flash","remainingFraction":0.96,"resetTime":"2026-05-10T17:29:03Z"},{"modelId":"gemini-3-flash-preview","remainingFraction":0.96,"resetTime":"2026-05-10T17:29:03Z"},{"modelId":"gemini-2.5-flash-lite","remainingFraction":1.0,"resetTime":"2026-05-11T14:56:55Z"},{"modelId":"gemini-3.1-flash-lite-preview","remainingFraction":1.0,"resetTime":"2026-05-11T14:56:55Z"}]}"#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        var runs: [CLICall] = []
        func add(_ request: URLRequest) { lock.withLock { stored.append(request) } }
        var requests: [URLRequest] { lock.withLock { stored } }
        func body(to path: String) -> String? {
            requests.last { $0.url?.path.hasSuffix(path) == true }.map { String(decoding: $0.httpBody ?? Data(), as: UTF8.self) }
        }
    }

    /// `answers` by path suffix: `(status, body)`; a token other than
    /// `fresh` is refused when `refuse` says so.
    private func make(token: String? = "fresh", quota: String = tiers, project: (Int, String) = (200, #"{"cloudaicompanionProject":"gen-lang-client-1"}"#),
                      refuseStale: Bool = false, located: Bool = true, seen: Seen = Seen()) throws -> (Provider, URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = home.appendingPathComponent(".gemini/oauth_creds.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let token { try Data(#"{"access_token":"\#(token)","refresh_token":"r","expiry_date":1}"#.utf8).write(to: file) }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.add(request)
            if refuseStale, request.value(forHTTPHeaderField: "Authorization") != "Bearer fresh" { return (Data(), StubbedProvider.response(401)) }
            if request.url?.path.hasSuffix(":loadCodeAssist") == true { return (Data(project.1.utf8), StubbedProvider.response(project.0)) }
            return (Data(quota.utf8), StubbedProvider.response(200))
        }
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willReturn(located ? "/opt/homebrew/bin/gemini" : nil)
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable _, _, _, _, _, _ in
                try? Data(#"{"access_token":"fresh","refresh_token":"r"}"#.utf8).write(to: file)
                return CLIResult(output: "")
            }
        let definition = try ProviderFactory.builtIn("gemini")
        var platform = Platform.current
        platform.runCLI = { @Sendable call in seen.runs.append(call); return cli }
        platform.processes = Processes.running { _ in cli }
        platform.keychain = { _ in (1, "") }
        platform.browserCookies = nil
        platform.browserStorage = nil
        let provider = Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { [platform] source, _ in
            DataSources.make(source, providerId: definition.id, platform: platform, network: network,
                             scripts: ProviderFactory.builtInScripts, environment: { _ in nil }, homeDirectory: home,
                             now: { Date(timeIntervalSince1970: 1778420000) })
        })
        return (provider, home)
    }

    @Test func `should be Gemini, on by default, with AI Studio as its dashboard`() throws {
        let (provider, _) = try make()
        #expect(provider.name == "Gemini")
        #expect(!provider.defaultAccount.isPaused)
        #expect(provider.plainDashboardURL?.absoluteString == "https://aistudio.google.com")
    }

    @Test func `should ask for the quota of the project Code Assist names, with the Gemini CLI's login`() async throws {
        let seen = Seen()
        let (provider, _) = try make(seen: seen)
        _ = try await provider.refreshPlain()
        #expect(seen.body(to: ":loadCodeAssist") == #"{"metadata":{"pluginType":"GEMINI"}}"#)
        #expect(seen.body(to: ":retrieveUserQuota") == #"{"project":"gen-lang-client-1"}"#)
        #expect(seen.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" })
    }

    @Test func `should still show the quotas when Code Assist names no project`() async throws {
        let seen = Seen()
        let (provider, _) = try make(project: (200, "{}"), seen: seen)
        #expect(try await provider.refreshPlain().quotas.count == 3)
        #expect(seen.body(to: ":retrieveUserQuota") == "{}")
    }

    @Test func `should show the quotas without a project after Code Assist fails three times to name one`() async throws {
        let seen = Seen()
        let (provider, _) = try make(project: (500, ""), seen: seen)
        #expect(try await provider.refreshPlain().quotas.count == 3)
        #expect(seen.requests.filter { $0.url?.path.hasSuffix(":loadCodeAssist") == true }.count == 3)
        #expect(seen.body(to: ":retrieveUserQuota") == "{}")
    }

    @Test func `should show one Pro, Flash and Flash Lite quota each at its lowest model, with no guessed window`() async throws {
        let (provider, _) = try make()
        let quotas = try await provider.refreshPlain().quotas
        #expect(quotas.map(\.quotaType) == [.modelSpecific("Pro"), .modelSpecific("Flash"), .modelSpecific("Flash Lite")])
        #expect(quotas.map(\.percentRemaining) == [88, 96, 100])
        // The response states no window, so none is guessed.
        #expect(quotas.allSatisfy { $0.window?.length == nil })
    }

    @Test func `should show a model outside the known tiers under its own name`() async throws {
        let (provider, _) = try make(quota: #"{"buckets":[{"modelId":"gemini-other","remainingFraction":0.5}]}"#)
        #expect(try await provider.refreshPlain().quotas.first?.quotaType == .modelSpecific("gemini-other"))
    }

    @Test func `should show when a quota resets as a moment and a countdown`() async throws {
        let (provider, _) = try make()
        let pro = try #require(try await provider.refreshPlain().quotas.first)
        #expect(pro.resetsAt == ISO8601DateFormatter().date(from: "2026-05-10T17:28:41Z"))
        #expect(pro.resetText == "Resets in 3h 55m")
    }

    @Test func `should fail when Gemini reports no quotas`() async throws {
        let (provider, _) = try make(quota: #"{"buckets":[]}"#)
        await #expect(throws: UsageError.parseFailed("No quota buckets in response")) { try await provider.refreshPlain() }
    }

    @Test func `should be unavailable when the Gemini CLI has no login on this Mac`() async throws {
        let (provider, _) = try make(token: nil)
        #expect(await provider.isPlainAvailable() == false)
    }

    @Test func `should renew a refused login by running the Gemini CLI, then show the quotas`() async throws {
        let seen = Seen()
        let (provider, home) = try make(token: "stale", refuseStale: true, seen: seen)
        #expect(try await provider.refreshPlain().quotas.count == 3)
        let run = try #require(seen.runs.first { $0.cli == "gemini" && $0.input == "/quit\n" })
        #expect(run.environment.unset.contains("GEMINI_API_KEY"))
        // Gemini's own file: ClaudeBar never writes it.
        let file = try String(contentsOf: home.appendingPathComponent(".gemini/oauth_creds.json"), encoding: .utf8)
        #expect(file == #"{"access_token":"fresh","refresh_token":"r"}"#)
    }

    @Test func `should ask to sign in again when the login is refused and the Gemini CLI isn't installed`() async throws {
        let (provider, _) = try make(token: "stale", refuseStale: true, located: false)
        await #expect(throws: UsageError.authenticationRequired) { try await provider.refreshPlain() }
    }

    @Test func `should read an added login from its own Gemini home, renewed by the Gemini CLI there`() async throws {
        let (provider, _) = try make()
        #expect(provider.accounts.form.map(\.id) == ["home"])
        let definition = try ProviderFactory.builtIn("gemini")
        let source = try #require(try definition.dataSources(forAccount: ["home": "/Users/me/gemini-work"]).first)
        guard case .refreshing(.jsonFile(let file), .cli(let call))? = source.credential else {
            Issue.record("Expected Gemini's login file renewed by its CLI"); return
        }
        #expect(file.path == "/Users/me/gemini-work/.gemini/oauth_creds.json")
        #expect(call.environment.set["GEMINI_CLI_HOME"] == "/Users/me/gemini-work")
        #expect(source.requiresFiles == ["/Users/me/gemini-work"])
    }
}
