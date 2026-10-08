import Foundation

/// The one money format for a shown cost — "$14.26", "$1,234.57". Every
/// cost string in the kernel reads through this, so no two spell a dollar
/// differently — and it spells it itself, since currency formatters differ
/// per platform (Windows puts a space in).
enum MoneyFormat {
    static func string(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let digits = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        let sign = digits.hasPrefix("-") ? "-" : ""
        let magnitude = digits.hasPrefix("-") ? String(digits.dropFirst()) : digits
        return sign + "$" + magnitude
    }
}
