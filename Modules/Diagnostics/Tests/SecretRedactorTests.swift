import Foundation
import Testing
@testable import Diagnostics

/// The law: a secret never appears in a log line ([CANONICAL_MODEL §5]).
/// `DataSource` registers every credential it touches; every line is scrubbed
/// before a sink sees it — so the law holds even when a caller forgets.
///
/// Each test mints its own credential (a UUID) and reads it once: the registry
/// is global and suites run in parallel — and since `DataSource` registers
/// every fetch's credential, it also holds other suites' dummy values, whose
/// forms may redact parts of a line no test here named. So a test pins what
/// the law promises — the secret it registered never survives a scrub — not a
/// pristine line.
@Suite struct SecretRedactorTests {
    @Test func `should scrub a registered credential from the line`() {
        let key = UUID().uuidString
        SecretRedactor.register(key)
        let scrubbed = SecretRedactor.scrub("HTTP fetch failed for https://api.x.com/?key=\(key)")
        #expect(!scrubbed.contains(key))
        #expect(scrubbed.contains("[redacted]"))
    }

    @Test func `should scrub the percent-encoded form of a credential`() {
        let key = "team & org/token+== \(UUID().uuidString)"
        SecretRedactor.register(key)
        // The form the credential rides in a URL, built the way a URL builds it.
        let encoded = key.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
        ) ?? key
        let scrubbed = SecretRedactor.scrub("refresh went to https://x.com/?id=\(encoded)")
        #expect(!scrubbed.contains(encoded))
        #expect(scrubbed.contains("[redacted]"))
    }

    @Test func `should scrub a credential however short`() {
        let key = String(UUID().uuidString.prefix(4))
        SecretRedactor.register(key)
        let scrubbed = SecretRedactor.scrub("the key \(key) was refused")
        #expect(!scrubbed.contains(key))
        #expect(scrubbed.contains("[redacted]"))
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
        let key = UUID().uuidString
        SecretRedactor.register(key)
        logger.error("Network error: token \(key) rejected")
        let written = sink.messages
        #expect(written.count == 1)
        #expect(!written[0].message.contains(key))
        #expect(written[0].message.contains("[redacted]"))
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
