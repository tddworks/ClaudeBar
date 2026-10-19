import Foundation

/// Secrets the credential store keeps, scrubbed from every log line before a
/// sink sees it — so the law holds ([CANONICAL_MODEL §5]: a secret never
/// appears in a log line) even when a caller forgets. The store registers
/// each value as it saves or reads it; `AppLog` replaces every occurrence —
/// raw, and as it would ride in a URL — with `[redacted]`.
public enum SecretRedactor {
    private static let registry = Registry()

    /// Registers a secret and the form it takes in a URL. Cheap to repeat:
    /// a value already known registers nothing. A value too short to be a
    /// secret — one a line could hold by chance — stays unregistered, so
    /// scrubbing never redacts ordinary words.
    public static func register(_ secret: String) {
        registry.register(secret, droppingShorterThan: Registry.minimumSecretLength)
    }

    /// Registers a credential the stores keep, whatever its length: the law
    /// has no length qualifier, and a short key deserves the same scrubbing
    /// as a long one. Every credential boundary calls this, never `register`.
    public static func registerCredential(_ credential: String) {
        registry.register(credential, droppingShorterThan: 1)
    }

    /// The line as a sink may print it: every registered secret `[redacted]`.
    public static func scrub(_ message: String) -> String {
        registry.scrub(message)
    }

    /// The known forms, behind one lock. Registered at the storage boundary;
    /// a line reads the set and replaces outside it, so a log call never
    /// holds the lock against another logger.
    private final class Registry: @unchecked Sendable {
        /// A generic value shorter than this could turn up in a line by
        /// chance; keeping it out spares the reader redacted words instead
        /// of secrets.
        static let minimumSecretLength = 8
        private let lock = NSLock()
        private var forms: [String] = []

        func register(_ secret: String, droppingShorterThan cutoff: Int) {
            guard secret.count >= cutoff else { return }
            var fresh = [secret]
            if let encoded = secret.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
            ), encoded != secret {
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
