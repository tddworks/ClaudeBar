import Foundation
import Observation

/// *Quota alerts* (#68): the person's own percentages — *tell me below 35%* —
/// beside the status alerts at 20% and empty. After each refresh it says once
/// that a login fell below one, and again only after the login climbed back a
/// point above it. It follows refreshes through `QuotaMonitor.onRefreshed`, so
/// the Monitor knows nothing of it ([design](docs/features/quota-alerts/design.md)).
@MainActor
@Observable
public final class QuotaAlerts {
    /// How many percentages the person can keep.
    nonisolated public static let most = 5
    /// Percentages the status alerts already say.
    nonisolated public static let alreadyAlerted: Set<Int> = [20, 0]

    /// Why a percentage wasn't added, in words Settings can print.
    public enum Refusal: Error, Equatable, LocalizedError {
        case notAPercent
        case alreadyAlerted(Int)
        case alreadyListed(Int)
        case full

        public var errorDescription: String? {
            switch self {
            case .notAPercent: "Enter a whole percent from 1 to 99."
            case .alreadyAlerted(let percent): "Already alerted — ClaudeBar tells you at \(percent)%."
            case .alreadyListed(let percent): "\(percent)% is already on the list."
            case .full: "Up to \(QuotaAlerts.most) percentages."
            }
        }
    }

    /// The person's percentages, highest first.
    public private(set) var percents: [Int]

    @ObservationIgnored private let settings: any QuotaAlertSettingsRepository
    @ObservationIgnored private let announcer: any QuotaAlertAnnouncer
    /// Per login, the percentages it was told it fell below and hasn't
    /// climbed back from. Kept in memory: after a relaunch a login still
    /// below is told once more.
    @ObservationIgnored private var told: [String: Set<Int>] = [:]

    public init(settings: any QuotaAlertSettingsRepository, announcer: any QuotaAlertAnnouncer) {
        self.settings = settings
        self.announcer = announcer
        self.percents = settings.quotaAlertPercents().sorted(by: >)
    }

    /// Adds what the person typed — `35` or `35%`.
    public func add(_ entry: String) throws(Refusal) {
        let digits = entry.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let percent = Int(digits), (0...99).contains(percent) else { throw .notAPercent }
        if Self.alreadyAlerted.contains(percent) { throw .alreadyAlerted(percent) }
        guard percent >= 1 else { throw .notAPercent }
        if percents.contains(percent) { throw .alreadyListed(percent) }
        guard percents.count < Self.most else { throw .full }
        keep(percents + [percent])
    }

    public func remove(_ percent: Int) {
        keep(percents.filter { $0 != percent })
    }

    /// After a refresh: tells each percentage `login` just fell below.
    /// `usage` is what the person sees — hidden quotas already left out.
    public func review(_ login: String, named name: String, usage: UsageSnapshot?) async {
        guard let left = usage.flatMap(Self.lowestShare) else { return }
        var below = told[login] ?? []
        var alerts: [QuotaAlert] = []
        for percent in percents {
            if left < Double(percent) {
                if below.insert(percent).inserted {
                    alerts.append(QuotaAlert(login: name, below: percent, left: Int(left.rounded(.down))))
                }
            } else if left >= Double(percent + 1) {
                below.remove(percent)
            }
        }
        told[login] = below
        for alert in alerts { await announcer.announce(alert) }
    }

    private func keep(_ list: [Int]) {
        percents = list.sorted(by: >)
        settings.setQuotaAlertPercents(percents)
    }

    /// The lowest share left among the quotas: a share as it is, money with a
    /// ceiling as its part of it; a balance without one has no share.
    private static func lowestShare(_ usage: UsageSnapshot) -> Double? {
        usage.quotas.compactMap { quota -> Double? in
            switch quota.left.shape {
            case .share(let percent): percent
            case .money(let money, of: let ceiling?) where ceiling.amount > 0:
                NSDecimalNumber(decimal: money.amount / ceiling.amount * 100).doubleValue
            case .money: nil
            }
        }.min()
    }
}
