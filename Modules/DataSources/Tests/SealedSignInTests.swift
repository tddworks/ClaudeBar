import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A sign-in an Electron app keeps sealed with its safeStorage key (#655):
/// opened before it is sent, the key read once and kept, read again when the
/// app has made a new one, and not asked for again at once when it couldn't
/// be read.
@Suite
struct SealedSignInTests {
    /// A key that opens what was sealed as the key's bytes then the value's.
    final class Keys: SafeStorageKeys, @unchecked Sendable {
        private let lock = NSLock()
        private var current: String?
        private var reads = 0

        init(_ key: String?) { current = key }

        func replace(with key: String?) { lock.withLock { current = key } }
        var keyReads: Int { lock.withLock { reads } }

        func key(app: String) throws -> Data {
            try lock.withLock {
                reads += 1
                guard let current else { throw SafeStorageKeyUnreadable(place: "\(app)'s key store") }
                return Data(current.utf8)
            }
        }

        func open(_ sealed: Data, with key: Data) -> Data? {
            sealed.starts(with: key) ? sealed.dropFirst(key.count) : nil
        }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
        var now: Date { lock.withLock { date } }
    }

    final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var headers: [String] = []
        func append(_ header: String?) { lock.withLock { headers.append(header ?? "") } }
        var all: [String] { lock.withLock { headers } }
    }

    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let sealing = SealedValues(prefix: "acme-sealed:v1:", app: "Acme")

    private func sealed(_ token: String, with key: String) -> String {
        sealing.prefix + Data((key + token).utf8).base64EncodedString()
    }

    private func source(storing token: String, safeStorage: SafeStorage?, sent: Sent) throws -> DataSource {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(#"{"token":"\#(token)"}"#.utf8).write(to: home.appendingPathComponent("login.json"))
        let lookup = try JSONDecoder().decode(CredentialLookup.self, from: Data(#"""
            {"jsonFile":{"path":"~/login.json","token":"$.token"},"sealed":{"prefix":"acme-sealed:v1:","app":"Acme"}}
            """#.utf8))
        let definition = DataSourceDefinition(kind: "api", credential: lookup,
                                              fetch: .http(HTTPRequest(url: "https://acme.test/usage",
                                                                       headers: ["Authorization": "Bearer {{token}}"])),
                                              mapping: .script(ScriptMapping(file: "none.js")))
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            sent.append(request.value(forHTTPHeaderField: "Authorization"))
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        var platform = Platform.bare
        platform.safeStorage = safeStorage
        return DataSources.make(definition, providerId: "acme", platform: platform, network: network,
                                environment: { _ in nil }, homeDirectory: home, now: { Date() })
    }

    private func failure(of source: DataSource) async -> String? {
        do {
            _ = try await source.fetchResponse()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test
    func `should send the sign-in opened when the app keeps it sealed`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent()
        let source = try source(storing: sealed("tok-1", with: "k1"), safeStorage: SafeStorage(Keys("k1")), sent: sent)

        _ = try await source.fetchResponse()

        #expect(sent.all == ["Bearer tok-1"])
    }

    @Test
    func `should send a sign-in an older app wrote in the clear as it is, never asking for a key`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent(), keys = Keys("k1")
        let source = try source(storing: "tok-clear", safeStorage: SafeStorage(keys), sent: sent)

        _ = try await source.fetchResponse()

        #expect(sent.all == ["Bearer tok-clear"])
        #expect(keys.keyReads == 0)
    }

    @Test
    func `should read the app's key once however many times the sign-in is read`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent(), keys = Keys("k1")
        let source = try source(storing: sealed("tok-1", with: "k1"), safeStorage: SafeStorage(keys), sent: sent)

        #expect(await source.isReady())
        _ = try await source.fetchResponse()
        _ = try await source.fetchResponse()

        #expect(sent.all == ["Bearer tok-1", "Bearer tok-1"])
        #expect(keys.keyReads == 1)
    }

    @Test
    func `should read the key again when the app has sealed its sign-in with a new one`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent(), keys = Keys("k1"), storage = SafeStorage(keys)
        _ = try await source(storing: sealed("tok-1", with: "k1"), safeStorage: storage, sent: sent).fetchResponse()

        keys.replace(with: "k2")
        _ = try await source(storing: sealed("tok-2", with: "k2"), safeStorage: storage, sent: sent).fetchResponse()

        #expect(sent.all == ["Bearer tok-1", "Bearer tok-2"])
        #expect(keys.keyReads == 2)
    }

    @Test
    func `should name where the key is kept when it can't be read, and not ask again within a minute`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent(), keys = Keys(nil), clock = Clock()
        let source = try source(storing: sealed("tok-1", with: "k1"), safeStorage: SafeStorage(keys, now: { clock.now }),
                                sent: sent)

        let first = await failure(of: source)
        clock.advance(SafeStorage.pause - 1)
        let again = await failure(of: source)

        #expect(first?.contains("Acme keeps its sign-in sealed, and its key (Acme's key store) couldn't be read") == true)
        #expect(again == first)
        #expect(keys.keyReads == 1)
        #expect(sent.all.isEmpty)

        keys.replace(with: "k1")
        clock.advance(1)
        _ = try await source.fetchResponse()

        #expect(keys.keyReads == 2)
        #expect(sent.all == ["Bearer tok-1"])
    }

    @Test
    func `should ask to sign in to the app again when its key doesn't open the sign-in, asking for the key again only after a minute`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent(), keys = Keys("new"), clock = Clock()
        let source = try source(storing: sealed("tok-1", with: "old"), safeStorage: SafeStorage(keys, now: { clock.now }),
                                sent: sent)

        let first = await failure(of: source)
        clock.advance(SafeStorage.pause - 1)
        let again = await failure(of: source)

        #expect(first?.contains("Acme's saved sign-in couldn't be opened with its key. Sign in to Acme again") == true)
        #expect(again == first)
        #expect(keys.keyReads == 1)
        #expect(sent.all.isEmpty)

        keys.replace(with: "old")
        clock.advance(1)
        _ = try await source.fetchResponse()

        #expect(keys.keyReads == 2)
        #expect(sent.all == ["Bearer tok-1"])
    }

    @Test
    func `should say a platform with no safeStorage can't open a sealed sign-in`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let sent = Sent()
        let source = try source(storing: sealed("tok-1", with: "k1"), safeStorage: nil, sent: sent)

        let failure = await failure(of: source)

        #expect(failure == "Opening a sign-in Acme keeps sealed isn't available on \(Platform.bare.name) yet.")
        #expect(sent.all.isEmpty)
    }
}
