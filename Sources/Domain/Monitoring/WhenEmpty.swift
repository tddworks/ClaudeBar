import Foundation
import Quotas

/// *Rest when empty*: where a product the person asked to rest is now. One
/// saved value per product, so a relaunch keeps it, and moved only by
/// `after`: a refresh that was seen, never a guess
/// (docs/features/monitoring/rest-when-empty/design.md).
public enum WhenEmpty: Sendable, Equatable {
    /// Not empty, or back from empty: drawn as usual.
    case watching
    /// Every counted login is out: dimmed and labelled, since then.
    case resting(since: Date)
    /// Empty, but the person asked to see it anyway: drawn as usual until it
    /// has had room again.
    case shownAnyway

    /// Where the product is after a refresh that read `status`: the
    /// product's status, `nil` while nothing was seen. Empty rests a watched
    /// product; room is the only way back; nothing seen changes nothing.
    public func after(_ status: QuotaStatus?, now: Date) -> WhenEmpty {
        guard let status else { return self }
        guard status == .depleted else { return .watching }
        return self == .watching ? .resting(since: now) : self
    }

    /// Whether the product is drawn dimmed, with *RESTING*.
    public var isResting: Bool {
        if case .resting = self { return true }
        return false
    }

    /// Since when it rests; `nil` while it doesn't.
    public var restingSince: Date? {
        if case let .resting(since) = self { return since }
        return nil
    }
}
