import Foundation

/// Reset times as CLIs print them for people — "2h 15m", "4:59pm
/// (America/New_York)", "Jan 15, 3:30pm", "Dec 25 at 4:59am", "Jan 1, 2026" —
/// turned into the next instant they name. A text format, not a vendor's:
/// a mapping script reaches it as `humanDate(text)`.
enum HumanDate {
    static func parse(_ text: String, now: Date) -> Date? {
        relative(text, now: now) ?? absolute(text, now: now)
    }

    /// "2d", "3h", "15m", "2 hours 5 min" — the sum of the first of each unit.
    private static func relative(_ text: String, now: Date) -> Date? {
        let units: [(pattern: String, seconds: TimeInterval)] = [
            (#"(\d+)\s*d(?:ays?)?"#, 86400),
            (#"(\d+)\s*h(?:ours?|r)?"#, 3600),
            (#"(\d+)\s*m(?:in(?:utes?)?)?"#, 60),
        ]
        var total: TimeInterval = 0
        for unit in units {
            if let range = text.range(of: unit.pattern, options: .regularExpression),
               let count = Int(text[range].filter(\.isNumber)) {
                total += Double(count) * unit.seconds
            }
        }
        return total > 0 ? now.addingTimeInterval(total) : nil
    }

    /// A date and/or time, optionally followed by an IANA zone in parentheses.
    private static func absolute(_ text: String, now: Date) -> Date? {
        let timeZone = zone(in: text)

        var cleaned = text.replacingOccurrences(of: #"\s+\d{1,3}%\s*(?:used|left)\s*$"#, with: "", options: .regularExpression)
        if let lastResets = cleaned.range(of: "resets", options: [.caseInsensitive, .backwards]) {
            cleaned = String(cleaned[lastResets.upperBound...])
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"\s*\([^)]+\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+at\s+"#, with: ", ", options: .regularExpression)

        let formats = [
            "MMM d, yyyy, h:mma", "MMM d, yyyy, ha", "MMM d, yyyy",
            "MMM d, h:mma", "MMM d, ha", "h:mma", "ha", "MMM d",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return future(date, format: format, timeZone: formatter.timeZone, now: now)
            }
        }
        return nil
    }

    private static func zone(in text: String) -> TimeZone? {
        guard let match = text.range(of: #"\(([^)]+)\)"#, options: [.regularExpression, .backwards]) else { return nil }
        let identifier = String(text[match].dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        return TimeZone(identifier: identifier)
    }

    /// The next occurrence of a date that came without a year, or without a day.
    private static func future(_ parsed: Date, format: String, timeZone: TimeZone, now: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let hasYear = format.contains("yyyy")
        let hasMonth = format.contains("MMM")
        let hasTime = format.contains("h") || format.contains("H")

        if hasYear { return parsed }

        if hasMonth {
            var components = hasTime
                ? calendar.dateComponents([.month, .day, .hour, .minute, .second], from: parsed)
                : calendar.dateComponents([.month, .day], from: parsed)
            if !hasTime {
                components.hour = 0
                components.minute = 0
                components.second = 0
            }
            components.year = calendar.component(.year, from: now)
            if let candidate = calendar.date(from: components), candidate > now { return candidate }
            components.year = calendar.component(.year, from: now) + 1
            return calendar.date(from: components) ?? parsed
        }

        if hasTime {
            let time = calendar.dateComponents([.hour, .minute, .second], from: parsed)
            var day = calendar.dateComponents([.year, .month, .day], from: now)
            day.hour = time.hour
            day.minute = time.minute
            day.second = time.second
            if let candidate = calendar.date(from: day), candidate > now { return candidate }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                day = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                day.hour = time.hour
                day.minute = time.minute
                day.second = time.second
                return calendar.date(from: day) ?? parsed
            }
        }
        return parsed
    }
}
