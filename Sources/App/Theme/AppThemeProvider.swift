import SwiftUI
import Domain

// MARK: - App Theme Provider Protocol

/// Protocol defining what a theme must provide.
/// All themes implement this protocol to ensure consistent styling across the app.
///
/// ## Design Principles
/// - **Protocol-Based**: Follows the same pattern as `ProviderSettingsRepository`
/// - **Pluggable**: New themes can be added by implementing this protocol
/// - **Type-Safe**: Compiler ensures all required properties are implemented
/// - **Composable**: Themes can inherit from base implementations
///
/// ## Usage
/// ```swift
/// @Environment(\.appTheme) var theme
///
/// Text("Hello")
///     .foregroundStyle(theme.textPrimary)
///     .font(.system(size: 14, design: theme.fontDesign))
/// ```
public protocol AppThemeProvider {
    // MARK: - Identity

    /// Unique identifier for the theme (e.g., "dark", "light", "cli", "christmas")
    var id: String { get }

    /// Display name shown in settings (e.g., "Dark", "Light", "CLI", "Christmas")
    var displayName: String { get }

    /// SF Symbol icon name for the theme picker
    var icon: String { get }

    /// Optional subtitle shown below the display name (e.g., "Terminal", "Festive")
    var subtitle: String? { get }

    /// SF Symbol icon for the menu bar. If nil, uses status-based icons.
    var statusBarIconName: String? { get }

    // MARK: - Background

    /// Main background gradient for the app
    var backgroundGradient: LinearGradient { get }

    /// Whether to show animated background orbs
    var showBackgroundOrbs: Bool { get }

    /// Optional overlay view (e.g., snowfall for Christmas theme)
    @MainActor var overlayView: AnyView? { get }

    // MARK: - Cards & Glass

    /// Card background gradient
    var cardGradient: LinearGradient { get }

    /// Glass effect background color
    var glassBackground: Color { get }

    /// Glass effect border color
    var glassBorder: Color { get }

    /// Glass effect highlight color (top edge shine)
    var glassHighlight: Color { get }

    /// Corner radius for cards and buttons
    var cardCornerRadius: CGFloat { get }

    /// Corner radius for pills and small elements
    var pillCornerRadius: CGFloat { get }

    // MARK: - Typography

    /// Primary text color (titles, main content)
    var textPrimary: Color { get }

    /// Secondary text color (subtitles, labels)
    var textSecondary: Color { get }

    /// Tertiary text color (hints, timestamps)
    var textTertiary: Color { get }

    /// Font design (default, rounded, monospaced, serif)
    var fontDesign: Font.Design { get }

    /// Custom font family name (e.g., "IBM Plex Mono"). When set, views use this instead of system font.
    var customFontName: String? { get }

    // MARK: - Status Colors

    /// Healthy status color (>50% remaining)
    var statusHealthy: Color { get }

    /// Warning status color (20-50% remaining)
    var statusWarning: Color { get }

    /// Critical status color (<20% remaining)
    var statusCritical: Color { get }

    /// Depleted status color (0% remaining)
    var statusDepleted: Color { get }

    // MARK: - Accents

    /// Primary accent color
    var accentPrimary: Color { get }

    /// Secondary accent color
    var accentSecondary: Color { get }

    /// Accent gradient for buttons and highlights
    var accentGradient: LinearGradient { get }

    /// Pill gradient for provider pills
    var pillGradient: LinearGradient { get }

    /// Share button gradient
    var shareGradient: LinearGradient { get }

    // MARK: - Interactive States

    /// Hover overlay color
    var hoverOverlay: Color { get }

    /// Pressed overlay color
    var pressedOverlay: Color { get }

    // MARK: - Progress Bar

    /// Progress bar track color
    var progressTrack: Color { get }

    // MARK: - Outlines, Shadows, Numbers

    /// How thick a card's, pill's or button's outline is — 1 for the glass
    /// themes, thicker for an outlined, printed look.
    var cardBorderWidth: CGFloat { get }

    /// A shadow under cards, pills and buttons — `nil` for none.
    var cardShadow: ThemeShadow? { get }

    /// The font for big numbers — percentages, totals, today's values;
    /// `nil` is the system font, bold, in `fontDesign`.
    var displayFontName: String? { get }

    /// Text drawn on a status colour (a badge), readable on all four.
    var textOnStatus: Color { get }

    // MARK: - Computed Helpers

    /// Returns the appropriate status color for a given quota status
    func statusColor(for status: QuotaStatus) -> Color

    /// The status colour of menu-bar text — on the system's light or dark
    /// strip, which the theme doesn't paint. Defaults to `statusColor(for:)`.
    func menuBarStatusColor(for status: QuotaStatus, darkMenuBar: Bool) -> Color

    /// Returns the appropriate progress gradient for a given percentage
    func progressGradient(for percent: Double) -> LinearGradient
}

// MARK: - Default Implementations

public extension AppThemeProvider {
    /// Default subtitle is nil
    var subtitle: String? { nil }

    /// Default status bar icon is nil (uses status-based icons)
    var statusBarIconName: String? { nil }

    /// Default custom font is nil (uses system font with fontDesign)
    var customFontName: String? { nil }

    /// Default overlay is nil
    @MainActor var overlayView: AnyView? { nil }

    var cardBorderWidth: CGFloat { 1 }
    var cardShadow: ThemeShadow? { nil }

    /// A printed, outlined theme (Pop): opaque paper instead of glass, ink
    /// outlines, inked selections and switches.
    var isOutlined: Bool { cardBorderWidth > 1 }
    var displayFontName: String? { nil }
    var textOnStatus: Color { .white }

    /// The font for a big number in this theme — the display font, else the
    /// system font at `weight` in `fontDesign`.
    func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if let displayFontName { return .custom(displayFontName, size: size) }
        return .system(size: size, weight: weight, design: fontDesign)
    }

    /// Default status color mapping
    func statusColor(for status: QuotaStatus) -> Color {
        switch status {
        case .healthy: statusHealthy
        case .warning: statusWarning
        case .critical: statusCritical
        case .depleted: statusDepleted
        }
    }

    func menuBarStatusColor(for status: QuotaStatus, darkMenuBar: Bool) -> Color {
        statusColor(for: status)
    }

    /// Default progress gradient based on percentage
    func progressGradient(for percent: Double) -> LinearGradient {
        let colors: [Color] = switch percent {
        case 0..<20: [statusCritical, statusDepleted]
        case 20..<50: [statusWarning, accentPrimary]
        default: [accentSecondary, statusHealthy]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Theme Font Helper

public extension AppThemeProvider {
    /// Returns the appropriate font for this theme — custom font if set, otherwise system font with fontDesign.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = customFontName {
            let suffix: String = switch weight {
            case .bold, .heavy, .black: "-Bold"
            case .semibold: "-SemiBold"
            case .medium: "-Medium"
            case .light, .ultraLight, .thin: "-Light"
            default: "-Regular"
            }
            return .custom("\(name)\(suffix)", size: size)
        }
        return .system(size: size, weight: weight, design: fontDesign)
    }
}

// MARK: - Base Theme

/// Base theme providing common defaults that other themes can inherit from.
/// This reduces duplication across theme implementations.
public struct BaseTheme {
    // Common status colors
    public static let defaultStatusHealthy = Color(red: 0.35, green: 0.92, blue: 0.68)
    public static let defaultStatusWarning = Color(red: 0.98, green: 0.72, blue: 0.35)
    public static let defaultStatusCritical = Color(red: 0.98, green: 0.42, blue: 0.52)
    public static let defaultStatusDepleted = Color(red: 0.85, green: 0.25, blue: 0.35)

    // Common accent colors
    public static let coralAccent = Color(red: 0.98, green: 0.55, blue: 0.45)
    public static let tealBright = Color(red: 0.35, green: 0.85, blue: 0.78)
    public static let goldenGlow = Color(red: 0.98, green: 0.78, blue: 0.35)

    // Purple palette
    public static let purpleDeep = Color(red: 0.38, green: 0.22, blue: 0.72)
    public static let purpleVibrant = Color(red: 0.55, green: 0.32, blue: 0.85)
    public static let pinkHot = Color(red: 0.85, green: 0.35, blue: 0.65)
    public static let magentaSoft = Color(red: 0.78, green: 0.42, blue: 0.75)
}

// MARK: - Theme Shadow

/// A shadow a theme puts under its cards: offset, colour, softness. A hard
/// printed shadow is `radius: 0`.
public struct ThemeShadow: Sendable, Equatable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat = 0, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

public extension View {
    /// The theme's card shadow, when it has one.
    @ViewBuilder
    func themeShadow(_ theme: any AppThemeProvider, scale: CGFloat = 1) -> some View {
        if let shadow = theme.cardShadow {
            self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x * scale, y: shadow.y * scale)
        } else {
            self
        }
    }
}

