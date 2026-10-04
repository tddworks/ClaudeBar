import Domain
import Foundation

/// *Map fields*' live card: a quota in the words the popover prints —
/// "62% left", "$12.40 of $50.00", "$12.40 remaining" for a balance.
enum QuotaPreview {
    static func text(_ quota: UsageQuota) -> String {
        switch quota.left {
        case .share(let percent):
            return "\(Int(percent.rounded()))% left"
        case .money(let remaining, let ceiling?):
            return "\(money(remaining)) of \(money(ceiling))"
        case .money(let remaining, nil):
            return "\(money(remaining)) remaining"
        }
    }

    static func money(_ money: Money) -> String {
        money.amount.formatted(.currency(code: money.currency).locale(Locale(identifier: "en_US")))
    }
}
