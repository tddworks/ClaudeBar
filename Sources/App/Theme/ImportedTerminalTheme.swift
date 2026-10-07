import SwiftUI
import Kit

// MARK: - RGBColor → SwiftUI Color

public extension TerminalColorScheme.RGBColor {
    /// Convert to SwiftUI `Color`.
    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(alpha)
    }
}

// MARK: - ImportedTerminalTheme

/// An ``AppThemeProvider`` implementation generated from an imported terminal color scheme.
///
/// Created by ``TerminalThemeGenerator`` and backed by pre-computed ``GeneratedThemeProperties``.
/// All SwiftUI colors are derived from the canonical ``TerminalColorScheme/RGBColor`` values.
public struct ImportedTerminalTheme: AppThemeProvider {
    private let props: GeneratedThemeProperties
    private let scheme: TerminalColorScheme

    /// Create a theme from generated properties and the original color scheme.
    public init(props: GeneratedThemeProperties, scheme: TerminalColorScheme) {
        self.props = props
        self.scheme = scheme
    }

    // MARK: - Identity

    public var id: String { props.id }
    public var displayName: String { props.displayName }
    public var icon: String { "terminal.fill" }
    public var subtitle: String? { "Imported" }
    public var statusBarIconName: String? { nil }

    // MARK: - Color Scheme Preference

    /// Whether this imported theme prefers a dark color scheme (derived from background luminance).
    public var prefersDarkColorScheme: Bool { props.isDark }

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [props.background.color, props.cardBackground.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { false }

    // MARK: - Cards & Glass

    public var cardGradient: LinearGradient {
        LinearGradient(
            colors: [props.cardBackground.color, props.cardBackground.color.opacity(0.95)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var glassBackground: Color { props.glassBackground.color }
    public var glassBorder: Color { props.glassBorder.color }
    public var glassHighlight: Color { props.glassHighlight.color }
    public var cardCornerRadius: CGFloat { 10 }
    public var pillCornerRadius: CGFloat { 12 }

    // MARK: - Typography

    public var textPrimary: Color { props.textPrimary.color }
    public var textSecondary: Color { props.textSecondary.color }
    public var textTertiary: Color { props.textTertiary.color }
    public var fontDesign: Font.Design { .monospaced }
    public var customFontName: String? { nil }

    // MARK: - Status Colors

    public var statusHealthy: Color { props.statusHealthy.color }
    public var statusWarning: Color { props.statusWarning.color }
    public var statusCritical: Color { props.statusCritical.color }
    public var statusDepleted: Color { props.statusDepleted.color }

    // MARK: - Accents

    public var accentPrimary: Color { props.accentPrimary.color }
    public var accentSecondary: Color { props.accentSecondary.color }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentPrimary, accentSecondary],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [accentPrimary.opacity(0.25), accentSecondary.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [scheme.yellow.color, scheme.brightYellow.color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { accentPrimary.opacity(0.1) }
    public var pressedOverlay: Color { accentPrimary.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { props.progressTrack.color }
}
