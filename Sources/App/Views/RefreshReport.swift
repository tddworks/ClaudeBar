import Kit
import Foundation

/// What the popover prints about a provider's last refresh — which data source
/// answered (*via RPC*, so a fallback is never silent), and which step failed
/// (*Couldn't read your key · Couldn't connect · Couldn't find the numbers*),
/// because each sends the person somewhere different. USER_JOURNEYS F1, F2.
struct RefreshReport: Equatable {
    struct Failure: Equatable {
        /// The step's words; `nil` when the failure isn't a step's.
        let headline: String?
        /// Today's message — the hint that says what to do.
        let detail: String
    }

    /// "Updated 2m ago · via RPC", or "Last seen 3h ago · via API" while the
    /// last refresh failed. `nil` with no usage yet.
    let freshness: String?
    let failure: Failure?
    /// The usage on screen is from before a failed refresh — shown dimmed.
    let isLastSeen: Bool

    init(age: String?, source: String?, error: UsageError?, step: DataSourceError.Step?, hasUsage: Bool) {
        isLastSeen = hasUsage && error != nil
        if hasUsage, let age {
            let when = (error == nil ? "Updated " : "Last seen ") + age
            freshness = source.map { "\(when) · via \($0)" } ?? when
        } else {
            freshness = nil
        }
        failure = error.map { Failure(headline: step.map(Self.headline(for:)), detail: $0.localizedDescription) }
    }

    /// What a login's last refreshes say.
    @MainActor
    static func of(_ account: Account) -> RefreshReport {
        RefreshReport(
            age: account.snapshot?.ageDescription,
            source: account.answeredByLabel,
            error: account.lastError,
            step: account.lastFailedStep,
            hasUsage: account.snapshot != nil
        )
    }

    static func headline(for step: DataSourceError.Step) -> String {
        switch step {
        case .lookup: "Couldn't read your key"
        case .fetch: "Couldn't connect"
        case .mapping: "Couldn't find the numbers"
        }
    }
}
