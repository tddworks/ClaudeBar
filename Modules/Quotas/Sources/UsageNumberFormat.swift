import Foundation

/// The one spelling of a usage number that isn't money — a count, a share, a
/// change — beside `MoneyFormat`. The chart, the card and a webhook's message
/// all read through this, so no two print the same figure differently.
public enum UsageNumberFormat {
    /// "19.5M", "1.2K", "500" — a count of tokens.
    public static func count(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000_000...: short(Double(tokens) / 1_000_000_000) + "B"
        case 1_000_000...: short(Double(tokens) / 1_000_000) + "M"
        case 1_000...: short(Double(tokens) / 1_000) + "K"
        default: "\(tokens)"
        }
    }

    /// "46%" — a part of a whole, 0…1.
    public static func share(_ share: Double) -> String {
        String(format: "%.0f%%", share * 100)
    }

    /// "+12%", "−8%" — a change against what came before, as a fraction.
    public static func change(_ change: Double) -> String {
        let percent = Int((abs(change) * 100).rounded())
        return (change < 0 && percent > 0 ? "\u{2212}" : "+") + "\(percent)%"
    }

    /// One decimal, without a trailing ".0" — "2.5", "500".
    private static func short(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
