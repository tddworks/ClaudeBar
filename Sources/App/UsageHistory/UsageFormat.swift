import Foundation

/// The one spelling of a usage number in the popover — money, tokens, a
/// share — so the chart, the heatmap and the mix never print the same figure
/// two ways.
enum UsageFormat {
    /// "$14.26", or "$1,234" when `whole`.
    static func money(_ amount: Decimal, whole: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = whole ? 0 : 2
        formatter.minimumFractionDigits = whole ? 0 : 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    /// "19.5M", "1.2K", "500".
    static func count(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000_000...: short(Double(tokens) / 1_000_000_000) + "B"
        case 1_000_000...: short(Double(tokens) / 1_000_000) + "M"
        case 1_000...: short(Double(tokens) / 1_000) + "K"
        default: "\(tokens)"
        }
    }

    /// "46%" — a part of a whole, 0…1.
    static func share(_ share: Double) -> String {
        String(format: "%.0f%%", share * 100)
    }

    /// One decimal, without a trailing ".0" — "2.5", "500".
    private static func short(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}