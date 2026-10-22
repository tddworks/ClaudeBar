import DataSources
import Quotas
import Foundation
import Mockable
import Testing
import Providers
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a successful refresh tells about the login itself: when its sign-in
/// expires — the earliest its own data sources can read — noted on the
/// account, kept through a failed refresh, forgotten when a refresh finds
/// nothing ([design](../../docs/features/alerting/login-expiry/design.md)).
@MainActor
@Suite
struct LoginExpiryTests {

    private static let usageOK = #"{ "five_hour": { "utilization": 10.0 } }"#

    // MARK: - Claude, as it really reads

    /// The real `claude.json`: the expiry lives in the `api` source's
    /// credential, in milliseconds, while the active source is `cli`.

    @Test
    func `should note when the login expires after a successful refresh`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let inThreeDays = claude.now.addingTimeInterval(3 * 24 * 3600).timeIntervalSince1970 * 1000
        try claude.writeCredentials(expiresAt: inThreeDays)
        given(claude.network).request(.any).willReturn((Data(Self.usageOK.utf8), ClaudeHarness.response(200)))
        let provider = try claude.provider()
        provider.configuration.use("api")   // the cli source runs a terminal, which a test cannot answer
        let account = provider.defaultAccount

        _ = try await provider.refresh(account)

        let days = account.loginExpiresAt.map {
            Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: claude.now),
                                           to: Calendar.current.startOfDay(for: $0)).day
        }
        #expect(days == 3)
    }

    @Test
    func `should forget the expiry when a refresh finds none anymore`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(expiresAt: claude.now.addingTimeInterval(3 * 24 * 3600).timeIntervalSince1970 * 1000)
        given(claude.network).request(.any).willReturn((Data(Self.usageOK.utf8), ClaudeHarness.response(200)))
        let provider = try claude.provider()
        provider.configuration.use("api")   // the cli source runs a terminal, which a test cannot answer
        let account = provider.defaultAccount
        _ = try await provider.refresh(account)
        #expect(account.loginExpiresAt != nil)

        // A key with neither refresh token nor expiry — an API-key login now.
        try claude.writeCredentials(refreshToken: nil, expiresAt: nil)
        _ = try await provider.refresh(account)

        #expect(account.loginExpiresAt == nil)
    }

    @Test
    func `should record nothing while the login is paused`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        try claude.writeCredentials(refreshToken: "test-refresh-token", expiresAt: claude.now.addingTimeInterval(3 * 24 * 3600).timeIntervalSince1970 * 1000)
        given(claude.network).request(.any).willReturn((Data(Self.usageOK.utf8), ClaudeHarness.response(200)))
        let provider = try claude.provider()
        provider.configuration.use("api")   // the cli source runs a terminal, which a test cannot answer
        let account = provider.defaultAccount
        account.pause()

        await #expect(throws: UsageError.paused) { try await provider.refresh(account) }

        #expect(account.loginExpiresAt == nil)
    }

    // MARK: - Earliest of several, and none

    /// The fetch answers 200 until `fails` is set, then 500.
    private final class Answer: @unchecked Sendable {
        var fails = false
    }

    /// A definition with two credential-bearing sources whose files hold
    /// different expiries, read out of a temporary home.
    private func expiring(
        first: TimeInterval, second: TimeInterval, home: URL, network: MockNetworkClient? = nil
    ) throws -> Provider {
        func write(_ name: String, expiresIn: TimeInterval) throws {
            let expiresAt = String(Int64(Date(timeIntervalSinceNow: expiresIn).timeIntervalSince1970 * 1000))
            try Data(#"{ "oauth": { "accessToken": "token-1", "expiresAt": \#(expiresAt) } }"#.utf8)
                .write(to: home.appendingPathComponent(name))
        }
        try write("credentials-a.json", expiresIn: first)
        try write("credentials-b.json", expiresIn: second)

        func source(_ kind: String, file: String) -> DataSourceDefinition {
            try! JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
            { "kind": "\(kind)",
              "credential": { "jsonFile": { "path": "\(home.path)/\(file)", "token": "$.oauth.accessToken", "expiresAt": "$.oauth.expiresAt" },
                              "refresh": { "oauth2": { "tokenURL": "https://auth.example.com/token", "clientId": "c",
                                                        "dueWhen": { "expiresAt": "expiresAt", "unit": "milliseconds", "skew": 300 } } } },
              "fetch": { "http": { "url": "https://api.acme.test/usage" } },
              "mapping": { "json": { "quotas": [ { "kind": "session", "at": "$", "usedPercent": "used" } ] } } }
            """.utf8))
        }
        let definition = ProviderDefinition(
            profile: ProviderProfile(id: "acme", name: "Acme"),
            dataSources: [source("api", file: "credentials-a.json"), source("alt", file: "credentials-b.json")],
            defaultDataSource: "api"
        )
        let stubbed = network ?? MockNetworkClient()
        if network == nil { given(stubbed).request(.any).willReturn((Data(#"{"used": 10}"#.utf8), ClaudeHarness.response(200))) }
        return Provider(
            definition: definition,
            settings: InMemoryProviderSettings(),
            makeDataSource: {
                DataSources.make($0, providerId: "acme", cliExecutor: MockCLIExecutor(), network: stubbed,
                                 makeTransport: { _, _, _, _ in MockRPCTransport() },
                                 environment: { _ in nil }, homeDirectory: home, now: { Date() })
            }
        )
    }

    /// A successful refresh notes the expiry; a failed one leaves it alone.
    /// Not Claude's definition — its `api` source caches, and a cached answer
    /// never fails.
    @Test
    func `should keep the expiry a failed refresh last read`() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("login-expiry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let answer = Answer()
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable _ in
            answer.fails
                ? (Data("{}".utf8), ClaudeHarness.response(500))
                : (Data(#"{"used": 10}"#.utf8), ClaudeHarness.response(200))
        }
        let provider = try expiring(first: 10 * 24 * 3600, second: 3 * 24 * 3600, home: home, network: network)
        let account = provider.defaultAccount
        _ = try await provider.refresh(account)
        let noted = try #require(account.loginExpiresAt)

        answer.fails = true
        await #expect(throws: (any Error).self) { try await provider.refresh(account) }

        #expect(account.loginExpiresAt == noted)
    }

    @Test
    func `should note the earliest expiry its data sources can read`() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("login-expiry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let provider = try expiring(first: 10 * 24 * 3600, second: 3 * 24 * 3600, home: home)
        let account = provider.defaultAccount

        _ = try await provider.refresh(account)

        let days = account.loginExpiresAt.map {
            Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                           to: Calendar.current.startOfDay(for: $0)).day
        }
        #expect(days == 3)
    }

    @Test
    func `should record nothing for a login no data source can read an expiry of`() async throws {
        let definition = ProviderDefinition(
            profile: ProviderProfile(id: "acme", name: "Acme"),
            dataSources: [try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
            { "kind": "api", "fetch": { "http": { "url": "https://api.acme.test/usage" } },
              "mapping": { "json": { "quotas": [ { "kind": "session", "at": "$", "usedPercent": "used" } ] } } }
            """.utf8))],
            defaultDataSource: "api"
        )
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Data(#"{"used": 10}"#.utf8), ClaudeHarness.response(200)))
        let provider = Provider(
            definition: definition, settings: InMemoryProviderSettings(),
            makeDataSource: {
                DataSources.make($0, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                                 makeTransport: { _, _, _, _ in MockRPCTransport() },
                                 environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory,
                                 now: { Date() })
            }
        )

        _ = try await provider.refresh(provider.defaultAccount)

        #expect(provider.defaultAccount.loginExpiresAt == nil)
    }
}
