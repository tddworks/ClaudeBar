import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

/// A data source's memory between refreshes — the cached usage (`cache.ttl`)
/// and a rate limit's end — seen through `fetchUsage()`.
@Suite
struct UsageMemoryTests {

    private let clock = TestClock()

    /// A data source whose n-th request answers `n * 10` percent used, or
    /// whatever `answer` says.
    private func source(cache: String?, network: MockNetworkClient) throws -> DataSource {
        let cacheJSON = cache.map { #","cache":\#($0)"# } ?? ""
        let definition = try JSONDecoder().decode(DataSourceDefinition.self, from: Data("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}}\(cacheJSON),
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """.utf8))
        let clock = self.clock
        return DataSources.make(
            definition,
            providerId: "test",
            cliExecutor: MockCLIExecutor(),
            network: network,
            makeTransport: { _, _, _, _ in MockRPCTransport() },
            environment: { _ in nil },
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { clock.now }
        )
    }

    private static func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    /// Answers the n-th request with `n * 10` percent used.
    private func counting() -> MockNetworkClient {
        let network = MockNetworkClient()
        let calls = Calls()
        given(network).request(.any).willProduce { @Sendable _ in
            (Data(#"{"used":\#(calls.next() * 10)}"#.utf8), Self.response(200))
        }
        return network
    }

    @Test
    func `usage within the ttl is served from memory`() async throws {
        let source = try source(cache: #"{"ttl":60}"#, network: counting())

        let first = try await source.fetchUsage()
        clock.advance(59)
        let second = try await source.fetchUsage()

        #expect(source.cacheTTL == 60)
        #expect(first.quota(for: .weekly)?.percentRemaining == 90)
        #expect(second.quota(for: .weekly)?.percentRemaining == 90)
    }

    @Test
    func `usage older than the ttl is fetched again`() async throws {
        let source = try source(cache: #"{"ttl":60}"#, network: counting())

        _ = try await source.fetchUsage()
        clock.advance(60)
        let second = try await source.fetchUsage()

        #expect(second.quota(for: .weekly)?.percentRemaining == 80)
    }

    @Test
    func `a ttl of zero fetches every time`() async throws {
        let source = try source(cache: #"{"ttl":0}"#, network: counting())

        _ = try await source.fetchUsage()
        let second = try await source.fetchUsage()

        #expect(second.quota(for: .weekly)?.percentRemaining == 80)
    }

    @Test
    func `without a cache every fetch asks again`() async throws {
        let source = try source(cache: nil, network: counting())

        _ = try await source.fetchUsage()
        let second = try await source.fetchUsage()

        #expect(source.cacheTTL == nil)
        #expect(second.quota(for: .weekly)?.percentRemaining == 80)
    }

    @Test
    func `a rate limit is honoured without asking again until it ends`() async throws {
        let network = MockNetworkClient()
        let calls = Calls()
        // Throttled once; any later request would succeed.
        given(network).request(.any).willProduce { @Sendable _ in
            calls.next() == 1
                ? (Data(), Self.response(429, ["Retry-After": "120"]))
                : (Data(#"{"used":25}"#.utf8), Self.response(200))
        }
        let source = try source(cache: nil, network: network)
        let limited = DataSourceError(.fetch, .rateLimited(retryAt: clock.now.addingTimeInterval(120)))

        await #expect(throws: limited) { try await source.fetchUsage() }
        clock.advance(119)
        await #expect(throws: limited) { try await source.fetchUsage() }
        clock.advance(1)
        let usage = try await source.fetchUsage()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 75)
    }
}

/// A clock a test moves forward.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Counts calls across a mock's closure.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
