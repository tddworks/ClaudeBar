import Foundation
import Testing

@testable import Infrastructure

@Suite("SingleFlightCache")
struct SingleFlightCacheTests {

    @Test("Recomputes only once for repeated lookups of the same key")
    func cachesRepeatedLookups() {
        let cache = SingleFlightCache<Int>()
        let counter = Counter()

        let first = cache.value(for: "k", ttl: { _ in 60 }, compute: { counter.next() })
        let second = cache.value(for: "k", ttl: { _ in 60 }, compute: { counter.next() })

        #expect(first == 1)
        #expect(second == 1)
        #expect(counter.count == 1)
    }

    @Test("Keeps separate values per key")
    func separatesKeys() {
        let cache = SingleFlightCache<String>()

        let a = cache.value(for: "a", ttl: { _ in 60 }, compute: { "value-a" })
        let b = cache.value(for: "b", ttl: { _ in 60 }, compute: { "value-b" })

        #expect(a == "value-a")
        #expect(b == "value-b")
    }

    @Test("Recomputes after the entry expires")
    func recomputesAfterExpiry() async throws {
        let cache = SingleFlightCache<Int>()
        let counter = Counter()

        let first = cache.value(for: "k", ttl: { _ in 0.05 }, compute: { counter.next() })
        try await Task.sleep(for: .milliseconds(120))
        let second = cache.value(for: "k", ttl: { _ in 0.05 }, compute: { counter.next() })

        #expect(first == 1)
        #expect(second == 2)
    }

    @Test("TTL can depend on the computed value")
    func ttlVariesByValue() async throws {
        let cache = SingleFlightCache<Int?>()
        let counter = Counter()

        // nil expires immediately, non-nil is long-lived — the shape BinaryLocator
        // relies on to retry missing tools sooner than found ones.
        let ttl: (Int?) -> TimeInterval = { $0 == nil ? 0.05 : 600 }

        let miss = cache.value(for: "k", ttl: ttl, compute: { nil })
        #expect(miss == nil)

        try await Task.sleep(for: .milliseconds(120))

        let hit = cache.value(for: "k", ttl: ttl, compute: { counter.next() })
        #expect(hit == 1)

        // Now cached with the long TTL, so a further lookup must not recompute.
        let cached = cache.value(for: "k", ttl: ttl, compute: { counter.next() })
        #expect(cached == 1)
    }

    @Test("Invalidating a key forces recomputation of only that key")
    func invalidateSingleKey() {
        let cache = SingleFlightCache<Int>()
        let counterA = Counter()
        let counterB = Counter()

        _ = cache.value(for: "a", ttl: { _ in 60 }, compute: { counterA.next() })
        _ = cache.value(for: "b", ttl: { _ in 60 }, compute: { counterB.next() })

        cache.invalidate("a")

        let a = cache.value(for: "a", ttl: { _ in 60 }, compute: { counterA.next() })
        let b = cache.value(for: "b", ttl: { _ in 60 }, compute: { counterB.next() })

        #expect(a == 2)
        #expect(b == 1)
    }

    @Test("Invalidating all keys forces recomputation everywhere")
    func invalidateAll() {
        let cache = SingleFlightCache<Int>()
        let counter = Counter()

        _ = cache.value(for: "a", ttl: { _ in 60 }, compute: { counter.next() })
        cache.invalidateAll()
        _ = cache.value(for: "a", ttl: { _ in 60 }, compute: { counter.next() })

        #expect(counter.count == 2)
    }

    @Test("Concurrent misses on one key collapse into a single computation")
    func collapsesConcurrentMisses() {
        let cache = SingleFlightCache<Int>()
        let counter = Counter()
        let results = Results()
        let waiters = 16

        // Real threads rather than tasks: the callers this protects are the
        // synchronous PTY runners, and blocking cooperative threads here would
        // risk starving the pool rather than exercising the lock.
        DispatchQueue.concurrentPerform(iterations: waiters) { _ in
            let value = cache.value(
                for: "shared",
                ttl: { _ in 60 },
                compute: {
                    // Widen the window so latecomers genuinely overlap.
                    Thread.sleep(forTimeInterval: 0.1)
                    return counter.next()
                }
            )
            results.append(value)
        }

        #expect(counter.count == 1)
        #expect(results.values.count == waiters)
        #expect(results.values.allSatisfy { $0 == 1 })
    }
}

/// Thread-safe collector for values produced across threads.
private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
}

/// Thread-safe call counter for asserting how often `compute` actually ran.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
