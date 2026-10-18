import Foundation

/// Pre-computed theme property values generated from a ``TerminalColorScheme``.
///
/// Contains all values needed to build an ``ImportedTerminalTheme`` in the App layer.
/// Uses ``TerminalColorScheme/RGBColor`` instead of SwiftUI `Color` to stay in Infrastructure.
public struct GeneratedThemeProperties: Sendable {
    public let id: String
    public let displayName: String
    public let isDark: Bool

    public let background: TerminalColorScheme.RGBColor
    public let cardBackground: TerminalColorScheme.RGBColor
    public let glassBackground: TerminalColorScheme.RGBColor
    public let glassBorder: TerminalColorScheme.RGBColor
    public let glassHighlight: TerminalColorScheme.RGBColor

    public let textPrimary: TerminalColorScheme.RGBColor
    public let textSecondary: TerminalColorScheme.RGBColor
    public let textTertiary: TerminalColorScheme.RGBColor

    public let statusHealthy: TerminalColorScheme.RGBColor
    public let statusWarning: TerminalColorScheme.RGBColor
    public let statusCritical: TerminalColorScheme.RGBColor
    public let statusDepleted: TerminalColorScheme.RGBColor

    public let accentPrimary: TerminalColorScheme.RGBColor
    public let accentSecondary: TerminalColorScheme.RGBColor

    public let progressTrack: TerminalColorScheme.RGBColor
}

/// Maps a ``TerminalColorScheme`` to ``GeneratedThemeProperties``.
///
/// The mapping uses ANSI color semantics:
/// - Red (ANSI 1) → `statusCritical`
/// - Green (ANSI 2) → `statusHealthy`
/// - Yellow (ANSI 3) → `statusWarning`
/// - Blue (ANSI 4) → `accentSecondary`
/// - Cyan (ANSI 6) → `accentPrimary`
/// - Background → `backgroundGradient`, derived card/glass colors
/// - Foreground/Bold → `textPrimary`, `textSecondary`, `textTertiary`
public struct TerminalThemeGenerator {

    /// Generate theme properties from a terminal color scheme.
    /// - Precondition: `scheme.isValid` must be true (exactly 16 ANSI colors).
    public static func generate(from scheme: TerminalColorScheme) -> GeneratedThemeProperties {
        precondition(scheme.isValid, "TerminalColorScheme must have exactly 16 ANSI colors")
        let sanitizedId = scheme.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)

        return GeneratedThemeProperties(
            id: "imported-\(sanitizedId)",
            displayName: scheme.name,
            isDark: scheme.isDark,
            background: scheme.background,
            cardBackground: scheme.background.lightened(by: 0.08),
            glassBackground: scheme.background.lightened(by: 0.05).withAlpha(0.8),
            glassBorder: scheme.black.withAlpha(0.5),
            glassHighlight: scheme.cyan.withAlpha(0.15),
            textPrimary: scheme.boldText ?? scheme.foreground,
            textSecondary: scheme.foreground,
            textTertiary: scheme.foreground.withAlpha(0.7),
            statusHealthy: scheme.green,
            statusWarning: scheme.yellow,
            statusCritical: scheme.red,
            statusDepleted: scheme.red.withAlpha(0.7),
            accentPrimary: scheme.cyan,
            accentSecondary: scheme.blue,
            progressTrack: scheme.selection ?? scheme.background.lightened(by: 0.15)
        )
    }
}
