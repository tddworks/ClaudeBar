import Foundation
import Quotas

/// What the page calls a quota. A quota carries facts — its name and, when the
/// provider stated it, its window — and no title of its own (CANONICAL_MODEL §5).
///
/// - `name`: what the person calls it — *Session*, *Weekly*, *Opus*.
/// - `short`: for tight places (the menu bar, the notch, the Touch Bar, a
///   Notify tile). *Session* and *Weekly* are names for a window, so they print
///   that window's length — *5h*, *7d* — but only when the provider stated it;
///   otherwise the name. A named quota (*Opus*, *Monthly*) keeps its name.
public struct QuotaLabel: Sendable, Equatable {
    public let name: String
    public let short: String

    public init(_ quota: UsageQuota) {
        name = quota.quotaType.displayName
        switch quota.quotaType {
        case .session, .weekly:
            short = quota.windowDuration.flatMap(Self.length) ?? name
        case .modelSpecific, .timeLimit:
            short = name
        }
    }

    /// A stated window's length in its largest whole unit: 30m, 5h, 7d.
    private static func length(_ seconds: TimeInterval) -> String? {
        guard seconds > 0, seconds.truncatingRemainder(dividingBy: 60) == 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}
