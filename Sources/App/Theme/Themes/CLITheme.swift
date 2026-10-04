import SwiftUI

// MARK: - CLI Theme

/// Minimalistic monochrome terminal theme with classic green accents.
/// Inspired by classic terminal aesthetics with pure black background
/// and sharp, functional design.
public struct CLITheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "cli"
    public let displayName = "CLI"
    public let icon = "terminal.fill"
    public let subtitle: String? = "Terminal"
    /// The outline of the session glyph (`terminal.fill`), so the menu bar
    /// shows one terminal that fills in while Claude Code is working.
    public let statusBarIconName: String? = "terminal"

    // MARK: - CLI-Specific Colors

    // Static definitions for reuse
    static let black = Color(red: 0.0, green: 0.0, blue: 0.0)
    static let charcoal = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let darkGray = Color(red: 0.15, green: 0.15, blue: 0.15)
    static let gray = Color(red: 0.45, green: 0.45, blue: 0.45)
    static let green = Color(red: 0.0, green: 0.85, blue: 0.35)
    static let greenDim = Color(red: 0.0, green: 0.55, blue: 0.22)
    static let amber = Color(red: 0.95, green: 0.75, blue: 0.2)
    static let red = Color(red: 0.95, green: 0.25, blue: 0.25)
    static let white = Color(red: 0.92, green: 0.92, blue: 0.92)
    static let whiteDim = Color(red: 0.65, green: 0.65, blue: 0.65)

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Self.black, Self.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { false }

    // MARK: - Cards & Glass

    public static let cardGradient = LinearGradient(
        colors: [Self.charcoal, Self.charcoal.opacity(0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public var cardGradient: LinearGradient { Self.cardGradient }

    public static let glassBackground = charcoal
    public var glassBackground: Color { Self.glassBackground }

    public static let glassBorder = darkGray
    public var glassBorder: Color { Self.glassBorder }

    public static let glassHighlight = gray.opacity(0.3)
    public var glassHighlight: Color { Self.glassHighlight }

    public var cardCornerRadius: CGFloat { 8 }   // Match original CLI
    public var pillCornerRadius: CGFloat { 8 }   // Match original CLI

    // MARK: - Typography

    public var textPrimary: Color { Self.white }
    public var textSecondary: Color { Self.whiteDim }
    public var textTertiary: Color { Self.gray }
    public var fontDesign: Font.Design { .monospaced }

    // MARK: - Status Colors

    public var statusHealthy: Color { Self.green }
    public var statusWarning: Color { Self.amber }
    public var statusCritical: Color { Self.red }
    public var statusDepleted: Color { Color(red: 0.65, green: 0.15, blue: 0.15) }

    // MARK: - Accents

    public var accentPrimary: Color { Self.green }
    public var accentSecondary: Color { Self.greenDim }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Self.green, Self.greenDim],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [Self.green.opacity(0.25), Self.green.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [Self.amber, Self.amber.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { Self.green.opacity(0.1) }
    public var pressedOverlay: Color { Self.green.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { Self.darkGray }

    // MARK: - Custom Progress Gradient

    public func progressGradient(for percent: Double) -> LinearGradient {
        let color: Color = switch percent {
        case 0..<20: statusCritical
        case 20..<50: statusWarning
        default: statusHealthy
        }
        return LinearGradient(
            colors: [color, color.opacity(0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Initializer

    public init() {}
}

// MARK: - CLI Glass Card Modifier

struct CLIGlassCardStyle: ViewModifier {
    @Environment(\.themeMode) private var themeMode
    var cornerRadius: CGFloat = 8  // Sharper corners for CLI aesthetic
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base card layer - flat dark background
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(themeMode.isCLI ? CLITheme.cardGradient : AppTheme.cardGradient(for: .dark))

                    // Simple border - thin green line for CLI
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            themeMode.isCLI ? CLITheme.glassBorder : AppTheme.glassBorder(for: .dark),
                            lineWidth: 1
                        )
                }
            )
    }
}

extension View {
    func cliGlassCard(cornerRadius: CGFloat = 8, padding: CGFloat = 12) -> some View {
        modifier(CLIGlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}
