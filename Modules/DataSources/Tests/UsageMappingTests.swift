import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

/// `usage` — ClaudeBar's own documented output, which an extension's script
/// prints: `quotas[]` (`type`, `percentRemaining`, `resetsAt`, `resetText`,
/// `dollarRemaining`) and `costUsage`. Read exactly as extensions are today.
@Suite
struct UsageMappingTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("usage-mapping-\(UUID().uuidString)", isDirectory: true)

    /// The usage a script printing `output` maps to. The script is there; what
    /// it prints comes from the program runner handed in.
    private func usage(_ output: String) async throws -> UsageSnapshot {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("probe"))
        let cli = MockCLIExecutor()
        given(cli).locate(.any).willProduce { $0 }
        given(cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willReturn(CLIResult(output: output))
        let definition = DataSourceDefinition(kind: "quotas", fetch: .script(ScriptCall(run: "probe", folder: folder.path)),
                                              mapping: .usage(UsageMapping()))
        return try await DataSources.make(definition, providerId: "ext-acme", cliExecutor: cli, network: MockNetworkClient(),
                                          makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { _ in nil },
                                          homeDirectory: folder, now: { Date() }).fetchUsage()
    }

    @Test
    func `should show each quota an extension prints as the kind its type names`() async throws {
        let usage = try await usage("""
        {"quotas":[{"type":"session","percentRemaining":85,"resetsAt":"2026-03-17T23:00:00Z"},
                   {"type":"weekly","percentRemaining":62},
                   {"type":"model:opus","percentRemaining":40},
                   {"type":"Requests","percentRemaining":12,"resetText":"Resets monthly"}]}
        """)

        #expect(usage.quota(for: .session)?.percentRemaining == 85)
        #expect(usage.quota(for: .session)?.resetsAt == ISO8601DateFormatter().date(from: "2026-03-17T23:00:00Z"))
        #expect(usage.quota(for: .weekly)?.percentRemaining == 62)
        #expect(usage.quota(for: .modelSpecific("opus"))?.percentRemaining == 40)
        #expect(usage.quota(for: .timeLimit("Requests"))?.resetText == "Resets monthly")
    }

    @Test
    func `should give a quota its conventional window, as extensions always had`() async throws {
        let usage = try await usage(#"{"quotas":[{"type":"session","percentRemaining":85}]}"#)

        #expect(usage.quota(for: .session)?.windowDuration == QuotaType.session.conventionalWindow.seconds)
    }

    @Test
    func `should show an extension's cost as money spent against its budget`() async throws {
        let usage = try await usage(#"{"costUsage":{"totalCost":10.26,"budget":50,"apiDuration":120}}"#)

        #expect(usage.costUsage?.totalCost == Decimal(string: "10.26"))
        #expect(usage.costUsage?.budget == 50)
        #expect(usage.costUsage?.apiDuration == 120)
    }

    @Test
    func `should fail at the mapping step when an extension prints neither quotas nor a cost`() async throws {
        await #expect { try await usage(#"{"metrics":[]}"#) } throws: { ($0 as? DataSourceError)?.step == .mapping }
    }
}
