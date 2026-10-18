import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// Z.ai on stubbed connections: the key comes from Settings, Claude Code's own
/// settings file (only when it points at a Z.ai host), or an environment
/// variable, and the host comes with it.
@MainActor @Suite
struct ZaiExecutionTests {
    nonisolated static let body = #"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"percentage":13},{"type":"TOKENS_LIMIT","unit":6,"percentage":46},{"type":"TIME_LIMIT","unit":5,"percentage":1}]}}"#

    /// Answers on `host` for the key `key` only; anything else is a 400.
    private func make(config: [String: Any]? = nil, platform: String? = nil, envVar: String? = nil,
                      vault: MemoryVault = MemoryVault(), environment: [String: String] = [:],
                      loginShell: [String: String] = [:], status: Int = 200, seen: Seen = Seen()) throws -> Provider {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if let config {
            let folder = home.appendingPathComponent(".claude")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("settings.json"))
        }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            guard request.url?.path == "/api/monitor/usage/quota/limit", request.timeoutInterval == 10,
                  request.value(forHTTPHeaderField: "Accept-Language") == "en-US,en" else {
                return (Data(), StubbedProvider.response(400))
            }
            seen.record(host: request.url?.host, key: request.value(forHTTPHeaderField: "Authorization"))
            return (Data(Self.body.utf8), StubbedProvider.response(status))
        }
        let settings = InMemoryProviderSettings()
        settings.setValue(platform, "platform", forProvider: "zai")
        settings.setValue(envVar, "glmAuthEnvVar", forProvider: "zai")
        let definition = try ProviderFactory.builtIn("zai")
        return Provider(definition: definition, settings: settings, makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), loginShell: { loginShell[$0] },
                             environment: { environment[$0] }, homeDirectory: home, now: { Date() })
        }, vault: vault)
    }

    final class Seen: @unchecked Sendable {
        private(set) var host: String?
        private(set) var key: String?
        func record(host: String?, key: String?) { self.host = host; self.key = key }
    }

    @Test func `should show Z.ai, on, with its subscription page as the dashboard`() throws {
        let provider = try make()
        #expect(provider.name == "Z.ai")
        #expect(!provider.defaultAccount.isPaused)
        #expect(provider.plainDashboardURL?.absoluteString == "https://z.ai/subscribe")
    }

    @Test func `should show the session, weekly and MCP quotas from api.z.ai when the key is saved in Settings`() async throws {
        let seen = Seen()
        let quotas = try await make(vault: MemoryVault(["zai.apiKey": "saved"]), seen: seen).refreshPlain().quotas
        #expect(quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("MCP")])
        #expect(quotas[0].window?.length == 18000)
        #expect(quotas[1].window?.length == 604800)
        #expect(quotas[2].window?.length == nil)
        #expect(seen.host == "api.z.ai")
        #expect(seen.key == "Bearer saved")
    }

    @Test(arguments: [("zhipu", "open.bigmodel.cn"), ("dev", "dev.bigmodel.cn")])
    func `should ask the chosen platform's host with the saved key`(_ platform: String, _ host: String) async throws {
        let seen = Seen()
        _ = try await make(platform: platform, vault: MemoryVault(["zai.apiKey": "saved"]), seen: seen).refreshPlain()
        #expect(seen.host == host)
    }

    @Test func `should use Claude Code's key and host when Claude Code's settings point at Z.ai`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "from-config", "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic"]]
        _ = try await make(config: config, seen: seen).refreshPlain()
        #expect(seen.host == "open.bigmodel.cn")
        #expect(seen.key == "Bearer from-config")
    }

    @Test func `should use a Z.ai provider entry from Claude Code's settings`() async throws {
        let seen = Seen()
        let config = ["providers": [["api_key": "from-provider", "base_url": "https://api.z.ai/api/anthropic"]]]
        _ = try await make(config: config, seen: seen).refreshPlain()
        #expect(seen.host == "api.z.ai")
        #expect(seen.key == "Bearer from-provider")
    }

    @Test func `should never send Claude Code's key to Z.ai when Claude Code's settings point elsewhere`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "anthropic-key", "ANTHROPIC_BASE_URL": "https://api.anthropic.com"]]
        await #expect(throws: UsageError.self) { try await make(config: config, seen: seen).refreshPlain() }
        #expect(seen.key == nil)
    }

    @Test func `should never send the key when Claude Code points at a look-alike of Z.ai's host`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "key", "ANTHROPIC_BASE_URL": "https://api.z.ai.example.com"]]
        await #expect(throws: UsageError.self) { try await make(config: config, seen: seen).refreshPlain() }
        #expect(seen.key == nil)
    }

    @Test func `should use the key from the environment variable the person named`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GLM_KEY", environment: ["MY_GLM_KEY": "from-env"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-env")
        #expect(seen.host == "api.z.ai")
    }

    @Test func `should find the key the person exported only in their login shell (#170)`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GLM_KEY", loginShell: ["MY_GLM_KEY": "from-shell"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-shell")
    }

    @Test func `should prefer the app's own environment to the login shell`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["ZAI_API_KEY": "from-env"], loginShell: ["ZAI_API_KEY": "from-shell"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-env")
    }

    @Test func `should use ZAI_API_KEY when the person named no variable`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["ZAI_API_KEY": "from-env"], seen: seen).refreshPlain()
        #expect(seen.key == "Bearer from-env")
    }

    @Test func `should fail to read usage when there is no key anywhere`() async throws {
        await #expect(throws: UsageError.self) { try await make().refreshPlain() }
    }

    @Test func `should use an added login's own key and platform, never the environment`() async throws {
        let seen = Seen()
        let vault = MemoryVault()
        let provider = try make(vault: vault, environment: ["ZAI_API_KEY": "from-env"], seen: seen)
        let work = try provider.accounts.add(filling: ["apiKey": "work", "platform": "zhipu"])
        _ = try await provider.refresh(work)
        #expect(seen.key == "Bearer work")
        #expect(seen.host == "open.bigmodel.cn")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.self) { try await provider.refresh(work) }
    }

    @Test(arguments: [401, 403]) func `should ask to sign in again when Z.ai refuses the key`(_ code: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await make(vault: MemoryVault(["zai.apiKey": "saved"]), status: code).refreshPlain()
        }
    }
}
