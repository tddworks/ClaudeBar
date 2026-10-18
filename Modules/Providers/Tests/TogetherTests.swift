import Foundation
import Providers
import Quotas
import Testing

/// `"together": true` — a definition's data sources answer together (an
/// extension's sections): every one runs, the usage is their union in the
/// definition's order, a failed one is left out of it and shows beside it as
/// fetch health, and the refresh fails only when all do (docs/features/providers/extensions/design.md).
@MainActor
@Suite
struct TogetherTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-\(UUID().uuidString)", isDirectory: true)

    private func write(_ name: String, _ json: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func provider(together: Bool = true) throws -> Provider {
        let json = """
        {"profile":{"id":"ext-acme","name":"Acme","links":{}},"together":\(together),
         "dataSources":[
          {"kind":"quotas","fetch":{"file":{"path":"\(folder.path)/quotas.json"}},"mapping":{"usage":{}}},
          {"kind":"cost","fetch":{"file":{"path":"\(folder.path)/cost.json"}},"mapping":{"usage":{}}}],
         "defaultDataSource":"quotas"}
        """
        let definition = try ProviderDefinition.parse(Data(json.utf8), origin: .extension)
        return ProviderFactory.make(definition, settings: InMemoryProviderSettings())
    }

    @Test
    func `should show what every data source reports, together`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("quotas.json", #"{"quotas":[{"type":"weekly","percentRemaining":62}]}"#)
        try write("cost.json", #"{"costUsage":{"totalCost":10.26,"apiDuration":0}}"#)
        let acme = try provider()

        let usage = try await acme.refreshPlain()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 62)
        #expect(usage.costUsage?.totalCost == Decimal(string: "10.26"))
    }

    @Test
    func `should show what the others report and the failure beside it when one data source fails`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("quotas.json", #"{"quotas":[{"type":"weekly","percentRemaining":62}]}"#)
        let acme = try provider()

        let usage = try await acme.refreshPlain()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 62)
        #expect(usage.costUsage == nil)
        #expect(acme.defaultAccount.snapshot?.quota(for: .weekly) != nil)
        #expect(acme.defaultAccount.lastError != nil)
    }

    @Test
    func `should fail only when every data source fails`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let acme = try provider()

        await #expect(throws: (any Error).self) { try await acme.refreshPlain() }
        #expect(acme.defaultAccount.lastError != nil)
    }

    @Test
    func `should show only the chosen data source's usage when they do not answer together`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("quotas.json", #"{"quotas":[{"type":"weekly","percentRemaining":62}]}"#)
        try write("cost.json", #"{"costUsage":{"totalCost":10.26,"apiDuration":0}}"#)
        let acme = try provider(together: false)

        let usage = try await acme.refreshPlain()

        #expect(usage.quota(for: .weekly) != nil)
        #expect(usage.costUsage == nil)
    }

    @Test
    func `should keep answering together after the provider is saved and read back`() throws {
        let definition = try provider().definition

        let again = try ProviderDefinition.parse(try JSONEncoder().encode(definition), origin: .extension)

        #expect(again.together)
    }
}
