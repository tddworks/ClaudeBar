import Foundation
import Testing

@testable import Infrastructure

/// Covers the caching layer wired onto `BinaryLocator`. The lookup logic itself
/// is exercised by `SingleFlightCacheTests`; these confirm the wiring keeps the
/// public contract intact, since every provider depends on it each refresh.
/// Serialized: these share process-wide static caches, so a concurrent
/// `invalidateCaches()` from a sibling test would corrupt the measurements.
@Suite("BinaryLocator caching", .serialized)
struct BinaryLocatorCachingTests {

    @Test("Repeated lookups return a stable, still-executable path")
    func repeatedLookupsAreStable() {
        // `sh` is guaranteed present on macOS and lives on the default PATH.
        let first = BinaryLocator.which("sh")
        let second = BinaryLocator.which("sh")

        #expect(first == second)
        if let first {
            #expect(FileManager.default.isExecutableFile(atPath: first))
        }
    }

    @Test("A missing tool resolves to nil consistently")
    func missingToolStaysNil() {
        let name = "claudebar-definitely-not-a-real-binary"

        #expect(BinaryLocator.which(name) == nil)
        #expect(BinaryLocator.which(name) == nil)
    }

    @Test("Lookups still resolve after cache invalidation")
    func survivesInvalidation() {
        let before = BinaryLocator.which("sh")

        BinaryLocator.invalidateCaches()

        let after = BinaryLocator.which("sh")
        #expect(before == after)
    }

    @Test("An already-executable absolute path resolves to itself")
    func acceptsAbsolutePaths() {
        // The shell `which` guard rejects '/', so absolute paths must be
        // short-circuited or every executor handed a resolved path fails.
        #expect(BinaryLocator.which("/bin/echo") == "/bin/echo")
    }

    @Test("A non-executable absolute path does not resolve")
    func rejectsNonExecutableAbsolutePaths() {
        #expect(BinaryLocator.which("/etc/hosts") == nil)
        #expect(BinaryLocator.which("/bin/claudebar-not-here") == nil)
    }

    @Test("Shell PATH is non-empty and stable across calls")
    func shellPathIsStable() {
        let first = BinaryLocator.shellPath()
        let second = BinaryLocator.shellPath()

        #expect(!first.isEmpty)
        #expect(first == second)
    }

    @Test("Cached shell PATH avoids re-spawning the login shell")
    func cachedShellPathIsCheap() {
        BinaryLocator.invalidateCaches()

        // First call pays for a login-shell spawn; the cached call must not.
        let coldStart = CFAbsoluteTimeGetCurrent()
        _ = BinaryLocator.shellPath()
        let cold = CFAbsoluteTimeGetCurrent() - coldStart

        let warmStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 { _ = BinaryLocator.shellPath() }
        let warm = CFAbsoluteTimeGetCurrent() - warmStart

        // 50 cached reads should cost far less than one spawn. Deliberately a
        // loose bound — this asserts "no subprocess", not a latency budget.
        #expect(warm < max(cold, 0.001))
    }
}
