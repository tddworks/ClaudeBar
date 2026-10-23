import Foundation
import Domain

/// The one spelling of a usage number in the popover — a value in a unit, a
/// share — so the chart, the heatmap and the mix never print the same figure
/// two ways. Money reads through the kernel's `MoneyFormat`; counts, shares
/// and changes through its `UsageNumberFormat`.
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
    static func count(_ tokens: Int) -> String { UsageNumberFormat.count(tokens) }

    /// "46%" — a part of a whole, 0…1.
    static func share(_ share: Double) -> String { UsageNumberFormat.share(share) }

    /// "+12%", "−8%" — a change against what came before, as a fraction.
    static func change(_ change: Double) -> String { UsageNumberFormat.change(change) }

    /// "21h 40m", or "5m 30s" under an hour.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600, minutes = total / 60 % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(total % 60)s"
    }
}
