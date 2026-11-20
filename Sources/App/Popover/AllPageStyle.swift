import Foundation

/// *All page style* — how each provider reads on the popover's All page
/// (Settings → General). It is the page's own choice of how to print: Rings
/// answer *which provider can I keep working with?*, Bars answer *how much
/// room do I have on each window, lined up?*
///
/// It chooses how a provider is printed and nothing else — the login a card
/// reads, the numbers, the status and the badge are the same either way
/// (docs/features/monitoring/all-providers/design.md).
public enum AllPageStyle: String, Sendable, CaseIterable {
    /// A card per provider, led by the quota that runs out first (today's All).
    case rings
    /// A row per provider, a line per quota the person watches.
    case bars

    /// What someone who never chose gets.
    public static let `default`: AllPageStyle = .rings

    /// The word the settings row and the page both use.
    public var displayLabel: String {
        switch self {
        case .rings: "Rings"
        case .bars: "Bars"
        }
    }
}
