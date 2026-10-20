import DataSources
import Foundation
import Mockable
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Diagnostics

/// The law: a secret never appears in a log line ([CANONICAL_MODEL §5]).
/// `DataSource` is its one holder — every credential a fetch touches,
/// whatever lookup found it and whatever refresh renewed it, registers with
/// the scrubber here. The token in these tests is a UUID: the registry is
/// global and suites run in parallel — it also holds other suites' dummy
/// values — so an assertion pins what the law promises, that the secret this
/// fetch registered never survives a scrub, not a pristine line.
@Suite
struct CredentialRegistrationTests {
    /// A vault in memory, keyed by provider and setting name.
    final class Vault: SecretStore, @unchecked Sendable {
        var secrets: [String: String]
        init(_ secrets: [String: String] = [:]) { self.secrets = secrets }
        func secret(_ name: String, provider: String) -> String? { secrets["\(provider).\(name)"] }
    }

    private func make(vault: Vault) throws -> DataSource {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        { "kind": "api", "credential": { "setting": "apiKey" },
          "fetch": { "http": { "url": "https://example.com/usage", "headers": { "Authorization": "Bearer {{token}}" } } },
          "mapping": { "json": { "quotas": [] } } }
        """.utf8))
        let network = MockNetworkClient()
        given(network).request(.matching { @Sendable _ in true })
            .willReturn((Data("{}".utf8), HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        return DataSources.make(
            definition, providerId: "acme",
            cliExecutor: MockCLIExecutor(), network: network,
            makeTransport: { _, _, _, _ in MockRPCTransport() },
            secrets: vault,
            environment: { _ in nil }, homeDirectory: FileManager.default.temporaryDirectory, now: { Date() }
        )
    }

    @Test
    func `should register the credential a fetch touches, however it arrived`() async throws {
        let key = UUID().uuidString
        let source = try make(vault: Vault(["acme.apiKey": key]))
        _ = try await source.fetchResponse()

        let scrubbed = SecretRedactor.scrub("fetch went to https://example.com/?key=\(key)")
        #expect(!scrubbed.contains(key))
        #expect(scrubbed.contains("[redacted]"))
    }

    @Test
    func `should scrub the credential from what a logger writes after the fetch`() async throws {
        let sink = CapturingSink()
        let logger = CategoryLogger(category: "probes", sinks: [sink])
        let key = UUID().uuidString
        let source = try make(vault: Vault(["acme.apiKey": key]))
        _ = try await source.fetchResponse()

        logger.error("Network error: token \(key) rejected")
        let written = sink.messages
        #expect(written.count == 1)
        #expect(!written[0].contains(key))
        #expect(written[0].contains("[redacted]"))
    }
}

private final class CapturingSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var messages: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    func write(_ level: LogLevel, category: String, message: String) {
        lock.lock(); lines.append(message); lock.unlock()
    }
}
