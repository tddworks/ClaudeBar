import Foundation
import Testing
@testable import Diagnostics

/// The law: a secret never appears in a log line ([CANONICAL_MODEL §5]).
/// `DataSource` registers every credential it touches; every line is scrubbed
/// before a sink sees it — so the law holds even when a caller forgets.
///
/// Each test mints its own credential (a UUID): the registry is global and
/// suites run in parallel, so a shared literal could answer another suite's
/// scrub.
@Suite struct SecretRedactorTests {
    private var credential: String { UUID().uuidString }

    @Test func `should scrub a registered credential from the line`() {
        let key = credential
        SecretRedactor.register(key)
        #expect(SecretRedactor.scrub("HTTP fetch failed for https://api.x.com/?key=\(key)")
            == "HTTP fetch failed for https://api.x.com/?key=[redacted]")
    }

    @Test func `should scrub the percent-encoded form of a credential`() {
        let key = "team & org/token+== \(credential)"
        SecretRedactor.register(key)
        #expect(SecretRedactor.scrub("refresh went to https://x.com/?id=team%20%26%20org/token%2B%3D%3D%20\(credential)")
            == "refresh went to https://x.com/?id=[redacted]")
    }

    @Test func `should scrub a credential however short`() {
        let key = String(credential.prefix(4))
        SecretRedactor.register(key)
        #expect(SecretRedactor.scrub("the key \(key) was refused") == "the key [redacted] was refused")
    }

    @Test func `should keep a line that names no credential`() {
        let line = "HTTP fetch: status 401"
        #expect(SecretRedactor.scrub(line) == line)
    }

    @Test func `should keep a blank from registering`() {
        let line = "nothing to hide"
        SecretRedactor.register("")
        #expect(SecretRedactor.scrub(line) == line)
    }

    @Test func `should scrub what a logger writes through its sinks`() {
        let sink = CapturingSink()
        let logger = CategoryLogger(category: "probes", sinks: [sink])
        let key = credential
        SecretRedactor.register(key)
        logger.error("Network error: token \(key) rejected")
        #expect(sink.messages.map(\.message) == ["Network error: token [redacted] rejected"])
    }
}

private final class CapturingSink: LogSink, @unchecked Sendable {
    struct Entry {
        let level: LogLevel
        let category: String
        let message: String
    }

    private let lock = NSLock()
    private var lines: [Entry] = []
    var messages: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    func write(_ level: LogLevel, category: String, message: String) {
        lock.lock()
        lines.append(Entry(level: level, category: category, message: message))
        lock.unlock()
    }
}
