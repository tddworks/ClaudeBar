import Foundation

/// The user-selectable text size for the stacked dual-window menu bar label.
///
/// Stacked rendering draws two quota windows inside the menu bar's fixed
/// content height, so the size choice is a readability trade-off: bigger text
/// is easier to glance, smaller text leaves more breathing room between the
/// two lines.
///
/// - `.small`: the original stacked size, and the default.
/// - `.medium` / `.large`: progressively bigger lines.
///
/// The concrete point sizes are a rendering concern and live in the App layer
/// next to the stacked renderer; Domain only models the user's choice.
public enum MenuBarStackedSize: String, Sendable, Equatable, CaseIterable {
    case small
    case medium
    case large

    /// The size used when the user has never chosen one, and the fallback for
    /// raw values this build does not recognize.
    public static let `default`: MenuBarStackedSize = .small

    /// Decodes a persisted raw value, falling back to `.default` for unknown
    /// strings, so a settings file written by a newer build (or edited by
    /// hand) never breaks an older build: it quietly renders small instead.
    public init(storedRawValue: String) {
        self = MenuBarStackedSize(rawValue: storedRawValue) ?? .default
    }

    /// Short label for the settings picker.
    public var displayLabel: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
