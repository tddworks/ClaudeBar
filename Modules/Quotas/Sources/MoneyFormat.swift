import Foundation

/// The one money format for a shown cost — "$14.26". Every cost string in
/// the kernel reads through this, so no two spell a dollar differently —
/// POSIX, so no platform slips a space into the amount.
enum MoneyFormat {
    static func string(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}
