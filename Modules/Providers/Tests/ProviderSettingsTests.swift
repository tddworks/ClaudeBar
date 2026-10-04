import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// *REGION*, *API KEY*, *CLI DATA FOLDER* on a provider no vendor ships: one
/// form, two scopes, filled into each login's data sources.
@MainActor
@Suite
struct ProviderSettingsTests {
    private static let acme = """
    {"profile":{"id":"acme","name":"Acme","links":{"dashboard":"https://console.{{setting.region.site}}/usage"}},
     "settings":[
       {"id":"region","label":"Region","scope":"account","default":"china",
        "kind":{"choice":[{"id":"china","label":"China","site":"acme.cn"},
                          {"id":"international","label":"International","site":"acme.com"}]}},
       {"id":"apiKey","label":"API key","scope":"account","kind":"secret"},
       {"id":"home","label":"CLI data folder","scope":"account","default":"/Users/me/.acme","kind":{"path":{"mustExist":true}}}],
     "dataSources":[{"kind":"api","credential":{"setting":"apiKey"},
       "fetch":{"http":{"url":"https://api.{{setting.region.site}}/usage","headers":{"Authorization":"Bearer {{token}}"}}},
       "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}],
     "defaultDataSource":"api"}
    """

    private let sent = Requests()
    private let settings = InMemoryProviderSettings()
    private let vault = MemoryVault()

    private func provider(paths: FakePaths = FakePaths(folders: ["/Users/me/.acme", "/Users/me/.acme-work"])) throws -> Provider {
        let definition = try ProviderDefinition.parse(Data(Self.acme.utf8))
        let network = MockNetworkClient()
        let sent = self.sent
        given(network).request(.any).willProduce { @Sendable request in
            sent.record(request)
            return (Data(#"{"used":10}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let vault = self.vault
        return Provider(
            definition: definition,
            settings: settings,
            accounts: settings.accounts(forProvider: "acme"),
            makeDataSource: { source, login in
                DataSources.make(source, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                                 makeTransport: { _, _, _, _ in MockRPCTransport() }, secrets: vault.scoped(to: login),
                                 environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
            },
            vault: vault,
            paths: paths
        )
    }

    @Test
    func `the default login runs with the setting's default`() async throws {
        let acme = try provider()
        try acme.set("apiKey", to: "sk-default")

        _ = try await acme.refresh(acme.defaultAccount)

        #expect(sent.hosts == ["api.acme.cn"])
    }

    @Test
    func `changing the region runs every login there from the next refresh`() async throws {
        let acme = try provider()
        try acme.set("apiKey", to: "sk-default")
        try acme.set("region", to: "international")

        _ = try await acme.refresh(acme.defaultAccount)

        #expect(sent.hosts == ["api.acme.com"])
        #expect(settings.value("region", forProvider: "acme") == "international")
        #expect(acme.defaultAccount.dashboardURL == URL(string: "https://console.acme.com/usage"))
    }

    @Test
    func `an added login's own region wins over the provider's`() async throws {
        let acme = try provider()
        let work = try acme.addAccount(filling: ["region": "international", "apiKey": "sk-work", "home": "/Users/me/.acme-work"])

        _ = try await acme.refresh(work)

        #expect(sent.hosts == ["api.acme.com"])
        #expect(sent.authorizations == ["Bearer sk-work"])
        #expect(work.dashboardURL == URL(string: "https://console.acme.com/usage"))
        #expect(work.values["apiKey"] == nil)
    }

    @Test
    func `Settings can tell a key is saved without ever showing it`() throws {
        let acme = try provider()
        let key = try #require(acme.definition.setting("apiKey"))
        #expect(acme.hasSaved(key, for: acme.defaultAccount) == false)

        try acme.set("apiKey", to: "sk-default")
        #expect(acme.hasSaved(key, for: acme.defaultAccount))
        #expect(acme.value(of: key, for: acme.defaultAccount) == nil)

        try acme.set("apiKey", to: nil)
        #expect(acme.hasSaved(key, for: acme.defaultAccount) == false)
    }

    @Test
    func `a choice that isn't one of its options is refused`() throws {
        let acme = try provider()
        #expect(throws: UsageError.executionFailed("Choose a Region from the list.")) {
            try acme.addAccount(filling: ["region": "mars", "apiKey": "sk", "home": "/Users/me/.acme-work"])
        }
        #expect(throws: UsageError.executionFailed("Choose a Region from the list.")) { try acme.set("region", to: "mars") }
    }

    @Test
    func `two logins never share a folder — the default login's included`() throws {
        let acme = try provider()
        #expect(throws: UsageError.self) {
            try acme.addAccount(filling: ["apiKey": "sk", "home": "/Users/me/.acme"])
        }
        _ = try acme.addAccount(filling: ["apiKey": "sk", "home": "/Users/me/.acme-work"])
        #expect(throws: UsageError.self) {
            try acme.addAccount(filling: ["apiKey": "sk-2", "home": "/Users/me/.acme-work"])
        }
        #expect(acme.accounts.count == 2)
    }

    @Test
    func `a key the vault does not keep leaves no account behind`() throws {
        let acme = try providerWith(vault: RefusingVault())
        #expect(throws: UsageError.executionFailed("ClaudeBar couldn't keep this key securely. The account wasn't added.")) {
            try acme.addAccount(filling: ["apiKey": "sk", "home": "/Users/me/.acme-work"])
        }
        #expect(acme.accounts.count == 1)
    }

    @Test
    func `a key the vault refuses to replace leaves the old key in place`() throws {
        let vault = ReplacementRefusingVault(["acme.apiKey": "sk-old"])
        let acme = try providerWith(vault: vault)

        #expect(throws: UsageError.self) { try acme.set("apiKey", to: "sk-new") }

        #expect(vault.secret("apiKey", provider: "acme") == "sk-old")
    }

    @Test
    func `a setting declared twice, at the top and in the account form, is refused`() {
        let json = Self.acme.replacingOccurrences(of: #""defaultDataSource":"api"}"#,
            with: #""defaultDataSource":"api","accounts":{"form":[{"id":"region","label":"Region","choices":["x"]}]}}"#)
        #expect(throws: DecodingError.self) { try ProviderDefinition.parse(Data(json.utf8)) }
    }

    private func providerWith(vault: any SecretVault) throws -> Provider {
        Provider(definition: try ProviderDefinition.parse(Data(Self.acme.utf8)), settings: settings,
                 makeDataSource: { source, _ in DataSources.make(source, providerId: "acme") },
                 vault: vault, paths: FakePaths(folders: ["/Users/me/.acme-work"]))
    }

    @Test
    func `Settings is shown the definition as the default login runs it`() throws {
        let acme = try provider()
        try acme.set("region", to: "international")

        guard case .http(let request)? = acme.definitionAsRun.dataSource("api")?.fetch else {
            Issue.record("Expected an http fetch")
            return
        }
        #expect(request.url == "https://api.acme.com/usage")
    }

    @Test
    func `Settings shows only what the default login uses`() throws {
        let json = #"""
        {"profile":{"id":"tool","name":"Tool"},"cli":"tool","defaultDataSource":"cli",
         "settings":[{"id":"home","label":"Home","scope":"account","kind":"path"},
                     {"id":"envVar","label":"Env","default":"TOOL_KEY"}],
         "dataSources":[{"kind":"cli","credential":{"environment":"{{setting.envVar}}"},
           "fetch":{"command":{"cli":"tool"}},"mapping":{"json":{"quotas":[]}}}],
         "accounts":{"patch":{"cli":{"fetch":{"command":{"environment":{"set":{"HOME":"{{account.home}}"}}}}}}}}
        """#
        let definition = try ProviderDefinition.parse(Data(json.utf8))
        #expect(definition.defaultLoginSettings.map(\.id) == ["envVar"])
        #expect(try ProviderDefinition.parse(Data(Self.acme.utf8)).defaultLoginSettings.map(\.id) == ["region", "apiKey"])
    }

    @Test
    func `import lists the host of every region a key may go to`() throws {
        let definition = try ProviderDefinition.parse(Data(Self.acme.utf8))
        #expect(definition.keyDestinations == ["api.acme.cn", "api.acme.com"])
    }
}

/// A vault that seems to save and keeps nothing — an ad-hoc build's Keychain.
final class RefusingVault: SecretVault, @unchecked Sendable {
    func secret(_ name: String, provider: String) -> String? { nil }
    func save(_ value: String, _ name: String, provider: String) {}
    @discardableResult func delete(_ name: String, provider: String) -> Bool { false }
}

/// A Keychain that keeps a key once, then seems to take a new value but
/// overwrites it with garbage — a replacement that doesn't read back.
private final class ReplacementRefusingVault: SecretVault, @unchecked Sendable {
    var secrets: [String: String]
    init(_ secrets: [String: String]) { self.secrets = secrets }
    func secret(_ name: String, provider: String) -> String? { secrets["\(provider).\(name)"] }
    func save(_ value: String, _ name: String, provider: String) {
        let key = "\(provider).\(name)"
        secrets[key] = secrets[key] == nil ? value : "corrupted"
    }
    @discardableResult func delete(_ name: String, provider: String) -> Bool { secrets.removeValue(forKey: "\(provider).\(name)") != nil }
}

/// What a stubbed network was sent, in order.
private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var hosts: [String] { lock.withLock { requests.compactMap { $0.url?.host } } }
    var authorizations: [String] { lock.withLock { requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") } } }
}
