import Foundation
import Mockable

/// Where the person's alert percentages are kept. A destination's own
/// repository, beside `HookSettingsRepository` — never a provider setting.
@Mockable
public protocol QuotaAlertSettingsRepository: Sendable {
    /// The percentages, whole numbers 1–99.
    func quotaAlertPercents() -> [Int]
    func setQuotaAlertPercents(_ percents: [Int])
}

/// *Claude · work is below 35% — 34% left*, as plain values.
public struct QuotaAlert: Sendable, Equatable {
    /// The login, as the lineup names it.
    public let login: String
    /// The product the login belongs to.
    public let providerId: String
    /// The person's percentage it fell below.
    public let below: Int
    /// What it has left, in whole percent.
    public let left: Int

    public init(login: String, providerId: String, below: Int, left: Int) {
        self.login = login
        self.providerId = providerId
        self.below = below
        self.left = left
    }
}
