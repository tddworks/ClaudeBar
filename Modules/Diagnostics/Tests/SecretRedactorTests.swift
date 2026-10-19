import Foundation
import Testing
@testable import Diagnostics

/// The law: a secret never appears in a log line ([CANONICAL_MODEL §5]).
/// The vault registers its values; every line is scrubbed before a sink
/// sees it — so the law holds even when a caller forgets.
@Suite struct SecretRedactorTests {
    @Test func `should scrub a registered secret from the line`() {
        SecretRedactor.register("sk-ant-api03-9f2e8d1c7b4a")
        #expect(SecretRedactor.scrub("HTTP fetch failed for https://api.x.com/?key=sk-ant-api03-9f2e8d1c7b4a")
            == "HTTP fetch failed for https://api.x.com/?key=[redacted]")
    }

    @Test func `should scrub the percent-encoded form of a secret`() {
        SecretRedactor.register("team & org/token+==")
        #expect(SecretRedactor.scrub("refresh went to https://x.com/?id=team%20%26%20org/token%2B%3D%3D")
            == "refresh went to https://x.com/?id=[redacted]")
    }

    @Test func `should keep a line that names no secret`() {
        SecretRedactor.register("sk-ant-api03-9f2e8d1c7b4a")
        let line = "HTTP fetch: status 401"
        #expect(SecretRedactor.scrub(line) == line)
    }

    @Test func `should not scrub a value too short to be a secret`() {
        SecretRedactor.register("abc")
        #expect(SecretRedactor.scrub("the abc of logging") == "the abc of logging")
    }

    @Test func `should scrub a registered credential however short`() {
        SecretRedactor.registerCredential("abc1234")
        #expect(SecretRedactor.scrub("the key abc1234 was refused") == "the key [redacted] was refused")
    }

    @Test func `should scrub what a logger writes through its sinks`() {
        let sink = CapturingSink()
        let logger = CategoryLogger(category: "probes", sinks: [sink])
        SecretRedactor.register("sk-ant-api03-9f2e8d1c7b4a")
        logger.error("Network error: token sk-ant-api03-9f2e8d1c7b4a rejected")
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
