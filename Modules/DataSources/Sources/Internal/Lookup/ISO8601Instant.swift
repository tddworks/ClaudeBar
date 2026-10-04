import Foundation

/// An ISO 8601 instant with any fraction of a second —
/// `2026-07-26T21:03:09.138930Z` — which `ISO8601DateFormatter` alone reads
/// only to milliseconds.
enum ISO8601Instant {
    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        if let dot = text.firstIndex(of: ".") {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
            let fraction = text[text.index(after: dot)..<end].prefix(3)
            let trimmed = text[..<dot] + (fraction.isEmpty ? "" : "." + fraction) + text[end...]
            if let date = formatter.date(from: String(trimmed)) { return date }
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
