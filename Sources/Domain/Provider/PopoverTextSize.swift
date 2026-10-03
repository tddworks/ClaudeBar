import Quotas
import DataSources
import Providers
import Foundation

/// The user-selectable text size for the menu bar popover.
///
/// On a hi-DPI display the popover's secondary text — the SESSION / WEEKLY card
/// labels, the reset countdowns, the "Vs …" comparison lines, the account's
/// freshness line — renders at 7–10pt, which is too small to read comfortably.
/// macOS' own Text Size setting cannot help: it only rescales *semantic*
/// fonts, and the popover pins every size explicitly with `.system(size:)`.
///
/// - `.small`: denser than today, for a popover that has to fit a lot.
/// - `.medium`: today's sizes, and the default.
/// - `.large` / `.extraLarge`: progressively bigger text, with the popover
///   widening to match (`PopoverContentWidth`).
///
/// The concrete multiplier is a rendering concern and lives in the App layer
/// next to the font wrapper that applies it; Domain models the user's choice.
public enum PopoverTextSize: String, Sendable, Equatable, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    /// The size used when the user has never chosen one, and the fallback for
    /// raw values this build does not recognize.
    public static let `default`: PopoverTextSize = .medium

    /// Decodes a persisted raw value, falling back to `.default` for unknown
    /// strings, so a settings file written by a newer build (or edited by
    /// hand) never breaks an older build: it quietly renders default instead.
    public init(storedRawValue: String) {
        self = PopoverTextSize(rawValue: storedRawValue) ?? .default
    }

    /// Short label for the settings control.
    public var displayLabel: String {
        switch self {
        case .small: "Small"
        case .medium: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}