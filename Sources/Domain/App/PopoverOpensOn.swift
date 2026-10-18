import Foundation

/// *Open on* — where the popover lands each time it opens (Settings → General).
public enum PopoverOpensOn: String, Sendable, CaseIterable {
    /// The page it was on, as the popover always did.
    case whereILeftIt
    /// The All page, every time.
    case all

    /// The page an open lands on, from the one it was left on.
    public func page(onOpening current: PopoverPage) -> PopoverPage {
        switch self {
        case .whereILeftIt: current
        case .all: .all
        }
    }
}
