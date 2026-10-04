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
                      status: Int = 200, seen: Seen = Seen()) throws -> Provider {
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
        let definition = try Providers.builtIn("zai")
        return Provider(definition: definition, settings: settings, makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: Providers.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: home, now: { Date() })
        }, vault: vault)
    }

    final class Seen: @unchecked Sendable {
        private(set) var host: String?
        private(set) var key: String?
        func record(host: String?, key: String?) { self.host = host; self.key = key }
    }

    @Test func `definition keeps Z.ai's identity and dashboard`() throws {
        let provider = try make()
        #expect(provider.name == "Z.ai")
        #expect(provider.defaultAccount.isEnabled)
        #expect(provider.defaultAccount.dashboardURL?.absoluteString == "https://z.ai/subscribe")
    }

    @Test func `a key saved in Settings goes to api.z.ai`() async throws {
        let seen = Seen()
        let quotas = try await make(vault: MemoryVault(["zai.apiKey": "saved"]), seen: seen).defaultAccount.refresh().quotas
        #expect(quotas.map(\.quotaType) == [.session, .weekly, .timeLimit("MCP")])
        #expect(quotas[0].window?.length == 18000)
        #expect(quotas[1].window?.length == 604800)
        #expect(quotas[2].window?.length == nil)
        #expect(seen.host == "api.z.ai")
        #expect(seen.key == "Bearer saved")
    }

    @Test(arguments: [("zhipu", "open.bigmodel.cn"), ("dev", "dev.bigmodel.cn")])
    func `the platform setting chooses the host for a saved key`(_ platform: String, _ host: String) async throws {
        let seen = Seen()
        _ = try await make(platform: platform, vault: MemoryVault(["zai.apiKey": "saved"]), seen: seen).defaultAccount.refresh()
        #expect(seen.host == host)
    }

    @Test func `Claude Code's env pointing at Z.ai gives its key and host`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "from-config", "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic"]]
        _ = try await make(config: config, seen: seen).defaultAccount.refresh()
        #expect(seen.host == "open.bigmodel.cn")
        #expect(seen.key == "Bearer from-config")
    }

    @Test func `a providers entry in Claude Code's settings is read too`() async throws {
        let seen = Seen()
        let config = ["providers": [["api_key": "from-provider", "base_url": "https://api.z.ai/api/anthropic"]]]
        _ = try await make(config: config, seen: seen).defaultAccount.refresh()
        #expect(seen.host == "api.z.ai")
        #expect(seen.key == "Bearer from-provider")
    }

    @Test func `a Claude Code config pointing elsewhere never sends its key to Z.ai`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "anthropic-key", "ANTHROPIC_BASE_URL": "https://api.anthropic.com"]]
        await #expect(throws: UsageError.self) { try await make(config: config, seen: seen).defaultAccount.refresh() }
        #expect(seen.key == nil)
    }

    @Test func `a look-alike host is not Z.ai`() async throws {
        let seen = Seen()
        let config = ["env": ["ANTHROPIC_AUTH_TOKEN": "key", "ANTHROPIC_BASE_URL": "https://api.z.ai.example.com"]]
        await #expect(throws: UsageError.self) { try await make(config: config, seen: seen).defaultAccount.refresh() }
        #expect(seen.key == nil)
    }

    @Test func `the key is read from the environment variable the person named`() async throws {
        let seen = Seen()
        _ = try await make(envVar: "MY_GLM_KEY", environment: ["MY_GLM_KEY": "from-env"], seen: seen).defaultAccount.refresh()
        #expect(seen.key == "Bearer from-env")
        #expect(seen.host == "api.z.ai")
    }

    @Test func `with no variable named, ZAI_API_KEY is read`() async throws {
        let seen = Seen()
        _ = try await make(environment: ["ZAI_API_KEY": "from-env"], seen: seen).defaultAccount.refresh()
        #expect(seen.key == "Bearer from-env")
    }

    @Test func `no key anywhere needs one`() async throws {
        await #expect(throws: UsageError.self) { try await make().defaultAccount.refresh() }
    }

    @Test func `an added account uses its own key and platform, never the environment`() async throws {
        let seen = Seen()
        let vault = MemoryVault()
        let provider = try make(vault: vault, environment: ["ZAI_API_KEY": "from-env"], seen: seen)
        let work = try provider.addAccount(filling: ["apiKey": "work", "platform": "zhipu"])
        _ = try await work.refresh()
        #expect(seen.key == "Bearer work")
        #expect(seen.host == "open.bigmodel.cn")
        vault.secrets["\(work.id).apiKey"] = nil
        await #expect(throws: UsageError.self) { try await work.refresh() }
    }

    @Test(arguments: [401, 403]) func `a refused key needs signing in again`(_ code: Int) async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await make(vault: MemoryVault(["zai.apiKey": "saved"]), status: code).defaultAccount.refresh()
        }
    }
}
