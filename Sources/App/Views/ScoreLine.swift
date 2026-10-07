import Foundation
import Kit

/// The score line across the top of a `.scoreLine` header, read from the
/// selected provider: who's playing and how it's doing, what's left of its
/// first quota as coins, the tab as the world, and the minutes until that
/// quota resets as the level's time.
struct ScoreLine: Equatable {
    let player: String
    let status: String
    let coins: String
    let world: String
    let time: String

    /// - Parameters:
    ///   - quotas: the selected provider's quotas, first one leading
    ///   - tab: the selected tab's place, counting from 1
    init(providerName: String, status: String, quotas: [UsageQuota], tab: Int, now: Date = Date()) {
        player = providerName.uppercased()
        self.status = status
        world = "1-\(tab)"

        let first = quotas.first
        if let balance = first?.dollarRemaining {
            coins = "\(NSDecimalNumber(decimal: balance).intValue)"
        } else if let first {
            coins = "\(Int(max(0, first.percentRemaining)))"
        } else {
            coins = "--"
        }

        if let resetsAt = first?.resetsAt {
            let minutes = Int((resetsAt.timeIntervalSince(now) / 60).rounded())
            time = String(format: "%03d", min(999, max(0, minutes)))
        } else {
            time = "---"
        }
    }
}
