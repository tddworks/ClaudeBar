import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A login's expiry — read only as its definition declares it (`dueWhen`),
/// from the credential the lookup finds. A data source that names no
/// credential, no expiry, or a store that holds none, says nothing
/// ([design](../../docs/features/alerting/login-expiry/design.md)).
@Suite
struct CredentialExpiryTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("credential-expiry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A store that holds the expiry in milliseconds beside the token.
    private func writeMilliseconds(_ expiresIn: TimeInterval) throws {
        let expiresAt = String(Int64((Date(timeIntervalSinceNow: expiresIn)).timeIntervalSince1970 * 1000))
        try file(#"""
        { "oauth": { "accessToken": "token-1", "refreshToken": "refresh-1", "expiresAt": \#(expiresAt) } }
        """#)
    }

    /// A store that holds the expiry as ISO-8601.
    private func writeISO8601(_ expiresIn: TimeInterval) throws {
        let stamp = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: expiresIn))
        try file(#"""
        { "key": "token-1", "refresh_token": "refresh-1", "expires_at": "\#(stamp)" }
        """#)
    }

    private func file(_ json: String, named name: String = "credentials.json") throws {
        try Data(json.utf8).write(to: folder.appendingPathComponent(name))
    }

    /// A definition whose lookup reads `credentials.json` and renews under
    /// the unit the test names.
    private func source(unit: String, field: String = "expiresAt") throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data(#"""
        { "kind": "api",
          "credential": { "firstOf": [ { "jsonFile": { "path": "\#(folder.path)/credentials.json", "token": "$.oauth.accessToken", "expiresAt": "$.oauth.expiresAt" } } ],
                          "refresh": { "oauth2": { "tokenURL": "https://auth.example.com/token", "clientId": "client-1",
                                                    "dueWhen": { "expiresAt": "\#(field)", "unit": "\#(unit)", "skew": 300 } } } },
          "fetch": { "http": { "url": "https://api.example.com/usage" } },
          "mapping": { "json": { "quotas": [] } } }
        """#.utf8))
    }

    private func make(_ definition: DataSourceDefinition) -> DataSource {
        let network = MockNetworkClient()
        let response = HTTPURLResponse(url: URL(string: "https://api.example.com")!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        given(network).request(.any).willReturn((Data("{}".utf8), response))
        return DataSources.make(
            definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
            makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { _ in nil },
            homeDirectory: FileManager.default.temporaryDirectory, now: { Date() }
        )
    }

    private func iso8601Source() throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data(#"""
        { "kind": "api",
          "credential": { "jsonFile": { "path": "\#(folder.path)/credentials.json", "token": "$.key", "expiresAt": "$.expires_at" },
                          "refresh": { "oauth2": { "tokenURL": "https://auth.example.com/token", "clientId": "client-1",
                                                    "dueWhen": { "expiresAt": "expiresAt", "unit": "iso8601", "skew": 300, "missingIsDue": false } } } },
          "fetch": { "http": { "url": "https://api.example.com/usage" } },
          "mapping": { "json": { "quotas": [] } } }
        """#.utf8))
    }

    @Test
    func `should read the expiry a definition declares, in the unit it declares`() throws {
        try writeMilliseconds(3 * 24 * 3600)

        let expiry = try make(source(unit: "milliseconds")).credentialExpiry()

        let days = expiry.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: $0)).day }
        #expect(days == 3)
    }

    @Test
    func `should read an ISO-8601 expiry the same way`() throws {
        try writeISO8601(30 * 24 * 3600)

        let expiry = try make(iso8601Source()).credentialExpiry()

        #expect(expiry != nil)
        #expect(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: try #require(expiry))).day! > 20)
    }

    @Test
    func `should say nothing when the store holds no expiry`() throws {
        try file(#"{ "oauth": { "accessToken": "token-1" } }"#)

        #expect(try make(source(unit: "milliseconds")).credentialExpiry() == nil)
    }

    @Test
    func `should say nothing when the definition declares no dueWhen`() throws {
        try writeMilliseconds(3 * 24 * 3600)
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data(#"""
        { "kind": "api",
          "credential": { "jsonFile": { "path": "\#(folder.path)/credentials.json", "token": "$.oauth.accessToken", "expiresAt": "$.oauth.expiresAt" } },
          "fetch": { "http": { "url": "https://api.example.com/usage" } },
          "mapping": { "json": { "quotas": [] } } }
        """#.utf8))

        #expect(try make(definition).credentialExpiry() == nil)
    }

    @Test
    func `should say nothing when the data source names no credential`() throws {
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data(#"""
        { "kind": "cli", "fetch": { "cli": { "cli": "acme", "args": ["/usage"] } }, "mapping": { "json": { "quotas": [] } } }
        """#.utf8))

        #expect(try make(definition).credentialExpiry() == nil)
    }

    @Test
    func `should say nothing when the store is gone`() throws {
        // No credentials file written.
        #expect(try make(source(unit: "milliseconds")).credentialExpiry() == nil)
    }
}
