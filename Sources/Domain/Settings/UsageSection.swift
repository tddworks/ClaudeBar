import Foundation

/// A section of the popover's usage area, under the quotas — each the
/// person's to show or hide in Settings → General (docs/settings.md).
/// Whether one shows until the person chooses is its own to say; the
/// sentences that name it are the App's.
public enum UsageSection: String, Sendable, CaseIterable {
    /// Today's Cost, Tokens and Working Time cards, and other apps' cards.
    case today
    /// The thirty-day chart.
    case lastThirtyDays
    /// The year as a heatmap.
    case lastYear
    /// The year's model mix.
    case modelMix
    /// The weekly recap on the All page.
    case weeklyRecap

    /// Shown until the person hides it. The year's two sections start
    /// hidden: they read a year of logs, and keep the popover short.
    public var isShownByDefault: Bool {
        switch self {
        case .today, .lastThirtyDays, .weeklyRecap: true
        case .lastYear, .modelMix: false
        }
    }

    /// Whether the section reads the year of usage (`UsageHistory.readYear`).
    public var readsTheYear: Bool {
        switch self {
        case .lastYear, .modelMix: true
        case .today, .lastThirtyDays, .weeklyRecap: false
        }
    }
}
