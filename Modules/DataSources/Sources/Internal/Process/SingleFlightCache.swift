import Foundation

/// Caches values by key and collapses concurrent misses for the same key into a
/// single computation.
///
/// Providers refresh in parallel, so without this every provider independently
/// spawns a login shell to answer the same `PATH` or `which` question. Callers
/// that arrive while a key is in flight wait for that result instead of starting
/// their own lookup.
///
/// Deliberately lock-based rather than an actor: the PTY runners call into this
/// from synchronous code on non-cooperative threads, where `await` is not
/// available.
final class SingleFlightCache<Value: Sendable>: @unchecked Sendable {

    private struct Entry {
        let value: Value
        let expiresAt: Date
    }

    private let condition = NSCondition()
    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    /// Returns the cached value for `key`, computing it when absent or expired.
    ///
    /// - Parameters:
    ///   - key: Cache key.
    ///   - ttl: Lifetime for a newly computed value. Evaluated against the result
    ///     so callers can expire "not found" answers sooner than successful ones.
    ///   - compute: Runs outside the lock, so distinct keys still resolve in
    ///     parallel while duplicate work on one key is suppressed.
    func value(
        for key: String,
        ttl: (Value) -> TimeInterval,
        compute: () -> Value
    ) -> Value {
        condition.lock()

        while true {
            if let entry = entries[key], entry.expiresAt > Date() {
                condition.unlock()
                return entry.value
            }
            // Someone else is already computing this key; wait for their answer.
            guard inFlight.contains(key) else { break }
            condition.wait()
        }

        inFlight.insert(key)
        condition.unlock()

        let value = compute()

        condition.lock()
        entries[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl(value)))
        inFlight.remove(key)
        condition.broadcast()
        condition.unlock()

        return value
    }

    /// Drops one key so the next lookup recomputes it.
    func invalidate(_ key: String) {
        condition.lock()
        entries.removeValue(forKey: key)
        condition.unlock()
    }

    /// Drops every cached entry. In-flight computations are unaffected.
    func invalidateAll() {
        condition.lock()
        entries.removeAll()
        condition.unlock()
    }
}
