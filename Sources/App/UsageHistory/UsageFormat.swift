import Foundation
import Domain

/// The one spelling of a usage number in the popover — a value in a unit, a
/// share — so the chart, the heatmap and the mix never print the same figure
/// two ways. Money reads through the kernel's `MoneyFormat`.
enum UsageFormat {
    /// A value in `unit`: money for cost ("$14.26", "$14" when `whole`), a
    /// count for tokens and cache ("19.5M").
    static func value(_ value: Double, in unit: Days.Unit, whole: Bool = false) -> String {
        switch unit {
        case .cost: money(Decimal(value), whole: whole)
        case .tokens, .cache: count(Int(value))
        }
    }

    /// "$14.26", or "$1,234" when `whole`.
    static func money(_ amount: Decimal, whole: Bool = false) -> String {
        MoneyFormat.string(amount, whole: whole)
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

    /// "+12%", "−8%" — a change against what came before, as a fraction.
    static func change(_ change: Double) -> String {
        let percent = Int((abs(change) * 100).rounded())
        return (change < 0 && percent > 0 ? "−" : "+") + "\(percent)%"
    }

    /// "21h 40m", or "5m 30s" under an hour.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600, minutes = total / 60 % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(total % 60)s"
    }

    /// One decimal, without a trailing ".0" — "2.5", "500".
    private static func short(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
