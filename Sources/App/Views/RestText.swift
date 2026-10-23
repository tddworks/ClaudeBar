import Foundation

/// The words of *Rest when empty*: the page's line, the Settings card and
/// row, the menu bar's tooltip. The domain says whether a product rests and
/// since when; this says it, and the views only render it
/// (docs/features/monitoring/rest-when-empty/design.md).
enum RestText {
    /// The label on a resting product's page, beside PAUSED's kind.
    static let label = "RESTING"

    /// The line beside the label: why, and since when.
    static func line(since: Date) -> String {
        "Every login is out · since \(since.formatted(date: .omitted, time: .shortened))"
    }

    /// The button that draws it as usual until it has had room.
    static let showAnyway = "Show anyway"

    /// The Settings card.
    static let cardTitle = "Rest when empty"
    static let cardSubtitle = "When every login has run out, dim this product until a refresh shows room. Its switch stays on."

    /// The product's row in Settings → Providers while it rests.
    static let row = "Resting until the reset"

    /// Added to a resting readout's tooltip in the menu bar.
    static let readoutSuffix = "· resting"
}
