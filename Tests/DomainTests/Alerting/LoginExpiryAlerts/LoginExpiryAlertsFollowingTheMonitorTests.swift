import DataSources
import Foundation
import Mockable
import Testing
@testable import Domain

/// *Login expiry* follows the Monitor's refreshes: what the login's own
/// credentials say is reviewed after each refresh, named as the lineup names
/// it — and the card reads the same ladder.
@MainActor
@Suite
struct LoginExpiryAlertsFollowingTheMonitorTests {
    private final class Tick: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_792_000_000)
    }

    private let tick = Tick()
    private let told = RecordingDestination()
    private let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("login-expiry-follow-\(UUID().uuidString)", isDirectory: true)

    private func alerts() -> LoginExpiryAlerts {
        LoginExpiryAlerts(destination: told, calendar: .utc, now: { [tick] in tick.date })
    }

    /// A Claude-like login: its credential file carries `expiresAt` in
    /// milliseconds, declared by the definition's `dueWhen` — `nil` days for
    /// a sign-in with no expiry in it at all.
    private func claude(expiresInDays days: Int?) throws -> Provider {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var oauth = ["accessToken": "token-1"]
        if let days { oauth["expiresAt"] = String(Int64((tick.date.addingTimeInterval(TimeInterval(days) * 24 * 3600)).timeIntervalSince1970 * 1000)) }
        try JSONSerialization.data(withJSONObject: ["oauth": oauth])
            .write(to: home.appendingPathComponent("credentials.json"))

        let expiryField = days == nil ? "" : ", \"expiresAt\": \"$.oauth.expiresAt\""
        let refreshClause = days == nil ? "" : ", \"refresh\": { \"oauth2\": { \"tokenURL\": \"https://auth.invalid/token\", \"clientId\": \"c\", \"dueWhen\": { \"expiresAt\": \"expiresAt\", \"unit\": \"milliseconds\", \"skew\": 300 } } }"
        let json = """
        {"profile":{"id":"claude","name":"Claude","links":{}},
         "dataSources":[{"kind":"stub",
                         "credential":{ "jsonFile": { "path": "\(home.path)/credentials.json", "token": "$.oauth.accessToken"\(expiryField) }\(refreshClause) },
                         "fetch":{"http":{"url":"https://stub.invalid/claude"}},"mapping":{"usage":{}}}],
         "defaultDataSource":"stub"}
        """
        let definition = try ProviderDefinition.parse(Data(json.utf8), origin: .custom)
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((
            Data(#"{"quotas": [{"type": "session", "percentRemaining": 60}]}"#.utf8),
            HTTPURLResponse(url: URL(string: "https://stub.invalid")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        ))
        return Provider(definition: definition, settings: LegacySettings(MockRepositoryFactory.makeSettingsRepository()), makeDataSource: { source, _ in
            DataSources.make(source, providerId: "claude", cliExecutor: NoCLIInTests(), network: network,
                             makeTransport: { _, _, _, _ in throw UsageError.executionFailed("no RPC in a stub") },
                             environment: { _ in nil }, homeDirectory: home, now: { [tick] in tick.date })
        })
    }

    private func monitor(_ product: Provider) -> QuotaMonitor {
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock(), statusPolicy: { .absolute })
        alerts().follow(monitor)
        return monitor
    }

    /// A clock the Monitor may sleep on without waiting.
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private struct NoCLIInTests: CLIExecutor {
        func locate(_ binary: String) -> String? { nil }
        func execute(binary: String, args: [String], input: String?, timeout: TimeInterval,
                     workingDirectory: URL?, autoResponses: [String: String]) async throws -> CLIResult {
            throw UsageError.cliNotFound(binary)
        }
    }

    @Test func `should warn once that a login expires soon when it refreshes`() async throws {
        let product = try claude(expiresInDays: 3)
        let monitor = monitor(product)

        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        #expect(told.loginExpiryAlerts == [LoginExpiryAlert(login: "Claude", providerId: "claude", days: 3)])
    }

    @Test func `should stay quiet about a login whose sign-in has no knowable expiry`() async throws {
        let product = try claude(expiresInDays: nil)
        let monitor = monitor(product)

        await monitor.refresh(providerId: "claude")

        #expect(told.loginExpiryAlerts.isEmpty)
    }

    @Test func `should let the card read how long the sign-in has left`() async throws {
        let alerts = alerts()
        let product = try claude(expiresInDays: 3)
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock(), statusPolicy: { .absolute })
        alerts.follow(monitor)

        #expect(alerts.warning(of: product.defaultAccount) == nil)
        await monitor.refresh(providerId: "claude")
        #expect(alerts.warning(of: product.defaultAccount)?.days == 3)

        // Renewal: a new sign-in, weeks out, takes the line away again.
        tick.date = tick.date.addingTimeInterval(24 * 3600)
        _ = try claude(expiresInDays: 20)
        await monitor.refresh(providerId: "claude")

        #expect(alerts.warning(of: product.defaultAccount) == nil)
    }
}
