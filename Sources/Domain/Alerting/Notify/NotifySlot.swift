import Foundation

/// One cell of the tile's metrics row: the provider and the window it stands
/// for, and the name that window wears on the tile.
///
/// A cell is identified by its provider and its window rather than by its
/// name, so a window that comes back wearing a different name is still the
/// same cell. The name is carried along because a cell whose window stopped
/// reporting keeps its place, and an empty cell still has to say which window
/// it stands for.
public struct NotifySlot: Sendable, Equatable, Hashable {
    /// The provider the window belongs to.
    public let providerId: String

    /// The window's key, as the provider's own quota type states it.
    public let quotaKey: String

    /// The window's name on the tile: "5h", "7d", "Claude 5h".
    public let windowLabel: String

    public init(providerId: String, quotaKey: String, windowLabel: String) {
        self.providerId = providerId
        self.quotaKey = quotaKey
        self.windowLabel = windowLabel
    }

    /// Whether two cells stand for the same window, whatever name each wears.
    public func standsFor(_ other: NotifySlot) -> Bool {
        providerId == other.providerId && quotaKey == other.quotaKey
    }
}
