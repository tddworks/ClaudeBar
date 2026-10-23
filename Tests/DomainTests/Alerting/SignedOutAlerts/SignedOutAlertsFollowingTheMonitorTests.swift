import DataSources
import Foundation
import Testing
@testable import Domain

/// *Signed out* follows the Monitor's refreshes, the failed ones too: the
/// error the login kept is read after each one, named as the lineup names it.
@MainActor
@Suite
struct SignedOutAlertsFollowingTheMonitorTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    /// The vendor's answer, which the test changes between refreshes: its
    /// usage, or a 401 the definition reads as a sign-in that ended.
    private final class Vendor: NetworkClient, @unchecked Sendable {
        var status: Int

        init(status: Int) { self.status = status }

        func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
            (Data(#"{"quotas": [{"type": "session", "percentRemaining": 60}]}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private struct NoCLI: CLIExecutor {
        func locate(_ binary: String) -> String? { nil }
        func execute(binary: String, args: [String], input: String?, timeout: TimeInterval,
                     workingDirectory: URL?, autoResponses: [String: String]) async throws -> CLIResult {
            throw UsageError.cliNotFound(binary)
        }
    }

    private let told = RecordingDestination()

    /// A product whose definition says what a 401 means, as Cline's does.
    private func monitor(_ vendor: Vendor) throws -> (QuotaMonitor, Provider) {
        let json = """
        {"profile":{"id":"claude","name":"Claude","links":{}},
         "dataSources":[{"kind":"api","credential":{"environment":"STUB_READY"},
                         "fetch":{"http":{"url":"https://stub.invalid/claude"}},"mapping":{"usage":{}},
                         "errors":{"http.401":{"sessionExpired":"Run `claude` in terminal to log in again."}}}],
         "defaultDataSource":"api"}
        """
        let definition = try ProviderDefinition.parse(Data(json.utf8), origin: .custom)
        let settings = LegacySettings(MockRepositoryFactory.makeSettingsRepository())
        let product = Provider(definition: definition, settings: settings, makeDataSource: { source, _ in
            DataSources.make(source, providerId: "claude", cliExecutor: NoCLI(), network: vendor,
                             makeTransport: { _, _, _, _ in throw UsageError.executionFailed("no RPC in a stub") },
                             environment: { $0 == "STUB_READY" ? "ready" : nil },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        })
        let monitor = QuotaMonitor(providers: kept([product]), clock: TestClock(), statusPolicy: { .absolute })
        SignedOutAlerts(destination: told).follow(monitor)
        return (monitor, product)
    }

    @Test func `should tell once when a login's refresh finds it signed out`() async throws {
        let (monitor, _) = try monitor(Vendor(status: 401))

        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        #expect(told.signedOutAlerts == [SignedOutAlert(login: "Claude", providerId: "claude",
                                                        hint: "Run `claude` in terminal to log in again.")])
    }

    @Test func `should tell the next sign-out after the login signed in again`() async throws {
        let vendor = Vendor(status: 401)
        let (monitor, _) = try monitor(vendor)

        await monitor.refresh(providerId: "claude")
        vendor.status = 200
        await monitor.refresh(providerId: "claude")
        vendor.status = 401
        await monitor.refresh(providerId: "claude")

        #expect(told.signedOutAlerts.count == 2)
    }

    @Test func `should stay quiet while the login refreshes fine`() async throws {
        let (monitor, _) = try monitor(Vendor(status: 200))

        await monitor.refresh(providerId: "claude")

        #expect(told.signedOutAlerts.isEmpty)
    }

    @Test func `should never tell about a paused login`() async throws {
        let (monitor, product) = try monitor(Vendor(status: 401))
        product.defaultAccount.pause()

        await monitor.refresh(providerId: "claude")

        #expect(told.alerts.isEmpty)
    }
}
