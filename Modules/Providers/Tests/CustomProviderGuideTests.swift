import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// The custom-provider guide's examples (docs/features/providers/custom/examples),
/// read as a person's `~/.claudebar/providers/<id>.json` and run against their
/// sample answers — so the guide can't drift from what ClaudeBar reads.
@MainActor @Suite
struct CustomProviderGuideTests {
    private static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/features/providers/custom/examples")

    private func example(_ name: String) throws -> (definition: ProviderDefinition, answer: Data) {
        let definition = try ProviderDefinition.parse(
            Data(contentsOf: Self.examples.appendingPathComponent("\(name).json")), origin: .custom)
        let answer = try Data(contentsOf: Self.examples.appendingPathComponent("\(name).response.json"))
        return (definition, answer)
    }

    /// The example run with its key saved and its API answering the sample.
    private func provider(_ name: String, saved: [String: String]? = nil,
                          environment: [String: String] = [:]) throws -> Provider {
        let (definition, answer) = try example(name)
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer acme-key" else {
                return (Data(), StubbedProvider.response(401))
            }
            return (answer, StubbedProvider.response(200))
        }
        let settings = InMemoryProviderSettings()
        let vault = MemoryVault(saved ?? ["\(definition.id).apiKey": "acme-key"])
        return Provider(definition: definition, settings: settings, accounts: settings.accounts(forProvider: definition.id),
                        makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, secrets: vault.scoped(to: login),
                             environment: { environment[$0] }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test(arguments: ["acme-code", "acme-credits"])
    func `should ask for the API key in Settings and on Add Account, and send it only to the provider's own host`(_ name: String) throws {
        let definition = try example(name).definition

        #expect(definition.defaultLoginSettings.map(\.id) == ["apiKey", "authEnvVar"])
        #expect(definition.accountSettings.map(\.id) == ["apiKey"])
        #expect(definition.keyDestinations == ["api.acme.example"])
    }

    @Test func `should show a 5-hour and a weekly limit from what is used of each`() async throws {
        let usage = try await provider("acme-code").refreshPlain()

        let session = try #require(usage.quotas.first { $0.quotaType == .session })
        let weekly = try #require(usage.quotas.first { $0.quotaType == .weekly })
        #expect(session.percentRemaining == 58)
        #expect(weekly.percentRemaining == 90)
        #expect(session.resetsAt == ISO8601DateFormatter().date(from: "2026-10-22T15:00:00Z"))
        #expect(session.windowDuration == TimeInterval(5 * 3600))
        #expect(weekly.windowDuration == TimeInterval(7 * 86400))
    }

    @Test func `should read the key from the environment variable it names when none is saved`() async throws {
        let usage = try await provider("acme-code", saved: [:], environment: ["ACME_API_KEY": "acme-key"]).refreshPlain()

        #expect(usage.quotas.contains { $0.quotaType == .session })
    }

    @Test func `should show credits as dollars left of the monthly limit`() async throws {
        let usage = try await provider("acme-credits").refreshPlain()

        let credits = try #require(usage.quotas.first)
        #expect(credits.quotaType == .modelSpecific("Monthly credits"))
        #expect(credits.left == .money(Money(Decimal(string: "12.40")!, currency: "USD"),
                                       of: Money(Decimal(50), currency: "USD")))
    }
}
