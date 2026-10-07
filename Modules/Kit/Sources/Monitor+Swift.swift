import ClaudeBarKit
import Foundation
import Observation

// The face of monitoring, providers, alerting and the leaderboard (MODULAR_DESIGN §5).
// Kotlin owns their state and its concurrency; a view reading it calls
// `KitObservation.track()` (every `body` does), so the kit's one change signal re-renders it.

extension QuotaMonitor: @retroactive @unchecked Sendable {}
extension Providers: @retroactive @unchecked Sendable {}
extension Provider: @retroactive @unchecked Sendable {}
extension Account: @retroactive @unchecked Sendable {}
extension Accounts: @retroactive @unchecked Sendable {}
extension Configuration: @retroactive @unchecked Sendable {}
extension ProductTab: @retroactive @unchecked Sendable {}
extension ProviderDefinition: @retroactive @unchecked Sendable {}
extension DataSourceDefinition: @retroactive @unchecked Sendable {}
extension Setting: @retroactive @unchecked Sendable {}
extension UsageHistory: @retroactive @unchecked Sendable {}
extension GuestPasses: @retroactive @unchecked Sendable {}
extension InUse: @retroactive @unchecked Sendable {}
extension ProviderWorkshop: @retroactive @unchecked Sendable {}
extension ProviderDraft: @retroactive @unchecked Sendable {}
extension ImportReview: @retroactive @unchecked Sendable {}
extension Response: @retroactive @unchecked Sendable {}
extension DataSourceError: @retroactive @unchecked Sendable {}
extension UsageError: @retroactive @unchecked Sendable {}
extension NotificationAlerter: @retroactive @unchecked Sendable {}
extension NotifyPublisher: @retroactive @unchecked Sendable {}
extension NotifyDeviceLink: @retroactive @unchecked Sendable {}
extension ClaudeBarKit.Leaderboard: @retroactive @unchecked Sendable {}
extension LeaderboardMembership: @retroactive @unchecked Sendable {}
extension LeaderboardUploader: @retroactive @unchecked Sendable {}
extension RankCard: @retroactive @unchecked Sendable {}
extension Standing: @retroactive @unchecked Sendable {}
extension Username: @retroactive @unchecked Sendable {}
extension ProfileLink: @retroactive @unchecked Sendable {}
extension DailyTokens: @retroactive @unchecked Sendable {}

// Read from the SwiftUI environment. `Observable` asks nothing of a type: the tracking comes
// from `KitObservation`, as for every other kit object.
extension NewSessions: @retroactive @unchecked Sendable, @retroactive Observable {}
extension QuotaAlerts: @retroactive @unchecked Sendable, @retroactive Observable {}

// MARK: - Construction shortcuts (Kotlin's default arguments don't cross)

extension QuotaMonitor {
    /// Refreshes one login, as the person asked for it.
    public func refresh(providerId: String) async {
        try? await refresh(providerId: providerId, kind: .interactive)
    }
}

// MARK: - Logins as a Swift collection

/// The logins in the person's order: `count`, `first`, `map`, `enumerated` as for any list.
extension Accounts: @retroactive RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { Int(size) }
    public subscript(position: Int) -> Account { all[position] }
}

// MARK: - Errors as a screen prints them

extension KotlinThrowable {
    /// The words a screen prints — what Swift's `localizedDescription` gave for the Swift errors.
    public var localizedDescription: String { message ?? description }
}

extension Provider {
    /// Refreshes one login as the person asked for it; throws the reason when no usage came back.
    public func refreshing(_ account: Account) async throws {
        let outcome = try await refresh(account: account, kind: .interactive)
        if let failed = outcome as? RefreshOutcome.Failed { throw KitRefusal(reason: failed.error.localizedDescription) }
    }

    /// *Test Connection* for the default login.
    public func testConnection() async -> ConnectionOutcome? {
        try? await testConnection(account: nil)
    }
}

extension Setting: @retroactive Identifiable {}

/// A Kotlin failure is a Swift `Error` too, so it can travel in a `Result` or be thrown.
extension KotlinThrowable: @retroactive Error {}

extension ConnectionOutcome {
    /// *Test Connection*'s answer as a `Result`: what came back, or the step that failed.
    public var result: Result<Response, DataSourceError> {
        if let answered = self as? ConnectionOutcome.Answered { return .success(answered.response) }
        return .failure((self as! ConnectionOutcome.Failed).error)
    }
}

// MARK: - Quota alerts

extension QuotaAlerts {
    /// How many percentages the person can keep.
    public static var most: Int { Int(companion.MOST) }

    /// Percentages the status alerts already say.
    public static var alreadyAlerted: Set<Int> { Set(companion.ALREADY_ALERTED.map { $0.intValue }) }

    /// The person's percentages, highest first.
    public var percentValues: [Int] {
        KitObservation.track()
        return percents.map { $0.intValue }
    }
}

// MARK: - The header badge

extension ProviderBadgeState {
    /// The badge's states as a Swift enum, for `switch`.
    public enum Shape: Equatable {
        case syncing, unavailable, notSetUp, usageOnly, awaitingData
        case quota(QuotaStatus)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .syncing: .syncing
        case .unavailable: .unavailable
        case .notSetUp: .notSetUp
        case .usageOnly: .usageOnly
        case .awaitingData: .awaitingData
        case .quota(let quota): .quota(quota.status)
        }
    }

    /// What the badge reads of `logins` — the tab's, or one login's.
    public static func of(_ logins: [Account], quotaStatus: QuotaStatus?) -> ProviderBadgeState {
        companion.reading(accounts: logins, quotaStatus: quotaStatus)
    }
}
