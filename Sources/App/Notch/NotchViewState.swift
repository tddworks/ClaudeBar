import Foundation
import Observation
import Domain

/// Everything the notch draws, in one Equatable value.
///
/// The driver resolves this from the monitors and hands it over whole, so the
/// window never reaches back into app state.
struct NotchContent: Equatable {
    /// The single activity worth showing, resolved by `NotchActivityResolver`.
    var activity: NotchActivity?

    /// Sessions worth listing in the expanded panel, most relevant first.
    var sessions: [ClaudeSession] = []

    /// The quotas closest to running out, most depleted first.
    var quotas: [UsageQuota] = []

    /// Today's usage, for the panel header.
    var today: DailyUsageStat?

    /// The quota the user chose to watch. Kept even while a session has the
    /// notch, so the gauge never disappears just because Claude is busy.
    var headline: UsageQuota?

    /// Whether a probe is in flight, which the notch shows rather than hides.
    var isRefreshing = false

    static let empty = NotchContent()
}

/// What the notch is currently showing, and how big it came out.
///
/// The window controller writes `content` and `metrics`; the SwiftUI content
/// writes `contentSize` back once it has laid itself out, which is what the
/// window uses to decide which clicks belong to the notch and which fall
/// through to the menu bar.
@MainActor
@Observable
final class NotchViewState {
    var content: NotchContent = .empty

    /// The measured notch region for the display the window sits on.
    var metrics: NotchMetrics = NotchMetrics(
        closedSize: CGSize(width: NotchMetrics.defaultWidth, height: NotchMetrics.defaultHeight),
        isPhysicalNotch: false
    )

    /// Whether the pointer is over the notch, expanding it into a panel.
    var isExpanded = false

    /// Size of the drawn notch, reported by the content after layout.
    var contentSize: CGSize = .zero

    /// What the panel does when its buttons are pressed. Supplied by the driver
    /// so the view stays free of app plumbing.
    var refresh: (() -> Void)?
    var snooze: (() -> Void)?

    var activity: NotchActivity? { content.activity }
}
