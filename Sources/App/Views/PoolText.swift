import Foundation
import Providers

/// The words of the pool line under a product's account chips: *240% left
/// across 3 logins*. The pool says the sum and how many logins it spans;
/// this says it as a sentence, and the view only renders it
/// (docs/features/providers/quota-pools/design.md).
enum PoolText {
    /// The line itself, and what VoiceOver reads — the sum in whole percent,
    /// never capped at 100. A pool spans two logins or more, so the count is
    /// always plural.
    static func line(for pool: Pool) -> String {
        "\(Int(pool.percent))% left across \(pool.count) logins"
    }

    /// The tooltip: what the sum is made of, and why over 100% is normal.
    static let help = "Each login's tightest window, added together. The logins refill independently, so over 100% is normal."
}
