import DataSources
import Quotas
import Foundation
import Mockable
import Providers

/// Runs `claude.json`'s real data sources — and the JavaScript its mappings
/// name — over stubbed connections and a temporary home directory. What the
/// old `ClaudeUsageProbe` / `ClaudeAPIUsageProbe` tests pinned is pinned here
/// against the definition and its scripts.
struct ClaudeHarness {
    let home: URL
    let network = MockNetworkClient()
    let cli = MockCLIExecutor()
    var environment: [String: String] = [:]
    /// What `security find-generic-password … -w` answers, if anything.
    var keychainPassword: String?
    var now: Date = Date()

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-harness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Data sources

    /// One of `claude.json`'s data sources: `cli`, `cliCost` or `api`.
    func dataSource(_ kind: String) throws -> DataSource {
        let definition = try Providers.builtIn("claude")
        guard let source = definition.dataSource(kind) else { throw DefinitionError.unknownDataSource("claude", kind) }
        return make(source)
    }

    /// A `Provider` built from `claude.json` over these connections.
    @MainActor
    func provider(
        settings: any MultiAccountSettingsRepository = InMemoryProviderSettings(),
        accounts: [ProviderAccountConfig] = [],
        guestPasses: GuestPasses? = nil
    ) throws -> Account {
        let definition = try Providers.builtIn("claude")
        return Provider(
            definition: definition,
            settings: settings,
            accounts: accounts,
            makeDataSource: make,
            guestPasses: guestPasses
        ).defaultAccount
    }

    private func make(_ source: DataSourceDefinition) -> DataSource {
        let environment = self.environment
        let password = keychainPassword
        let now = self.now
        return DataSources.make(
            source,
            providerId: "claude",
            cliExecutor: cli,
            network: network,
            makeTransport: { _, _, _, _ in MockRPCTransport() },
            security: { arguments in
                guard arguments.first == "find-generic-password", let password else { return (44, "") }
                return (0, password)
            },
            scripts: Providers.builtInScripts,
            environment: { environment[$0] },
            homeDirectory: home,
            now: { now }
        )
    }

    // MARK: - Reading screens and responses

    /// The `/usage` screen through `claude-usage-screen.js`. Throws the
    /// `UsageError` the screen means, as the old probe did.
    func readUsageScreen(_ screen: String) throws -> UsageSnapshot {
        try unwrapped { try dataSource("cli").read(Response(text: screen)) }
    }

    /// Raw terminal bytes, drawn by the terminal emulator first — what the
    /// `cli` fetch does with `"screen": "rendered"`.
    func readRawUsageScreen(_ raw: String) throws -> UsageSnapshot {
        try readUsageScreen(TerminalRenderer(cols: 160, rows: 50).render(raw))
    }

    /// The `/cost` screen through `claude-cost-screen.js`.
    func readCostScreen(_ screen: String) throws -> UsageSnapshot {
        try unwrapped { try dataSource("cliCost").read(Response(text: screen)) }
    }

    /// A usage API body through claude.json's JSON mapping, with the plan the
    /// credential would carry. Throws the `UsageError` the old probe threw.
    func readAPIResponse(_ json: String, subscriptionType: String? = nil) async throws -> UsageSnapshot {
        try writeCredentials(subscriptionType: subscriptionType)
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Data(json.utf8), Self.response(200)))
        let definition = try Providers.builtIn("claude")
        let now = self.now
        let source = DataSources.make(
            definition.dataSource("api")!,
            providerId: "claude",
            cliExecutor: cli,
            network: network,
            makeTransport: { _, _, _, _ in MockRPCTransport() },
            scripts: Providers.builtInScripts,
            environment: { _ in nil },
            homeDirectory: home,
            now: { now }
        )
        return try await fetchUsage(source)
    }

    /// `fetchUsage()`, throwing the `UsageError` inside a `DataSourceError`.
    func fetchUsage(_ source: DataSource) async throws -> UsageSnapshot {
        do {
            return try await source.fetchUsage()
        } catch let failure as DataSourceError {
            throw failure.reason
        }
    }

    private func unwrapped(_ read: () throws -> UsageSnapshot) throws -> UsageSnapshot {
        do {
            return try read()
        } catch let failure as DataSourceError {
            throw failure.reason
        }
    }

    // MARK: - Files

    /// `~/.claude.json` with the account fields the CLI data source reads.
    func writeClaudeConfig(email: String? = nil, displayName: String? = nil, billingType: String? = nil, extra: [String: Any] = [:]) throws {
        var account: [String: Any] = [:]
        if let email { account["emailAddress"] = email }
        if let displayName { account["displayName"] = displayName }
        if let billingType { account["billingType"] = billingType }
        var config = extra
        if !account.isEmpty { config["oauthAccount"] = account }
        try JSONSerialization.data(withJSONObject: config).write(to: home.appendingPathComponent(".claude.json"))
    }

    func readClaudeConfig() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".claude.json"))) as? [String: Any] ?? [:]
    }

    /// `~/.claude/.credentials.json`.
    func writeCredentials(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAt: Double? = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
        subscriptionType: String? = nil,
        extra: [String: Any] = [:]
    ) throws {
        let directory = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var oauth: [String: Any] = extra
        oauth["accessToken"] = accessToken
        if let refreshToken { oauth["refreshToken"] = refreshToken }
        if let expiresAt { oauth["expiresAt"] = expiresAt }
        if let subscriptionType { oauth["subscriptionType"] = subscriptionType }
        try JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
            .write(to: directory.appendingPathComponent(".credentials.json"))
    }

    func readCredentials() throws -> [String: Any] {
        let url = home.appendingPathComponent(".claude/.credentials.json")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return document?["claudeAiOauth"] as? [String: Any] ?? [:]
    }

    /// A separate Claude config folder (`CLAUDE_CONFIG_DIR`) signed in as
    /// `email`: its `.claude.json` and `.credentials.json`.
    @discardableResult
    func writeLogin(in name: String, email: String?, token: String = "token") throws -> URL {
        let folder = home.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config: [String: Any] = email.map { ["oauthAccount": ["emailAddress": $0]] } ?? [:]
        try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent(".claude.json"))
        let oauth: [String: Any] = [
            "accessToken": token, "subscriptionType": "pro",
            "expiresAt": Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000,
        ]
        try JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
            .write(to: folder.appendingPathComponent(".credentials.json"))
        return folder
    }

    static func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }
}
