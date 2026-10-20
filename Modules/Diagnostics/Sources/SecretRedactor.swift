import Foundation

/// Credentials the fetches touch, scrubbed from every log line before a sink
/// sees it — so the law holds ([CANONICAL_MODEL §5]: a secret never appears
/// in a log line) even when a caller forgets. `DataSource` registers every
/// credential it touches, whatever lookup found it and whatever refresh
/// renewed it; `AppLog` replaces every occurrence — raw, and as it would
/// ride in a URL — with `[redacted]`.
public enum SecretRedactor {
    private static let registry = Registry()

    /// Registers a credential and the form it takes in a URL, whatever its
    /// length — the law has no length qualifier. Cheap to repeat: a value
    /// already known registers nothing.
    public static func register(_ credential: String) {
        registry.register(credential)
    }

    /// The line as a sink may print it: every registered credential
    /// `[redacted]`.
    public static func scrub(_ message: String) -> String {
        registry.scrub(message)
    }

    /// The known forms, behind one lock. Registered where the credential is
    /// used; a line reads the set and replaces outside it, so a log call
    /// never holds the lock against another logger.
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var forms: [String] = []

        func register(_ credential: String) {
            guard !credential.isEmpty else { return }
            var fresh = [credential]
            if let encoded = credential.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
            ), encoded != credential {
                fresh.append(encoded)
            }
            lock.lock()
            defer { lock.unlock() }
            for form in fresh where !forms.contains(form) {
                forms.append(form)
            }
        }

        func scrub(_ message: String) -> String {
            lock.lock()
            let known = forms
            lock.unlock()
            var scrubbed = message
            for form in known where scrubbed.contains(form) {
                scrubbed = scrubbed.replacingOccurrences(of: form, with: "[redacted]")
            }
            return scrubbed
        }
    }
}
