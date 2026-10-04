import SwiftUI
import Domain
import CoreText

// MARK: - Pop Theme

/// A chunky, friendly theme: cream dotted paper, thick ink outlines, hard
/// offset shadows, candy-coloured status, and big numbers in Lilita One.
/// Design: design-concept/claudebar-pop-theme.html.
public struct PopTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "pop"
    public let displayName = "Pop"
    public let icon = "paintpalette.fill"
    public let subtitle: String? = "Cute"

    // MARK: - Palette

    static let cream = Color(red: 0.992, green: 0.961, blue: 0.918)    // #FDF5EA
    static let paper = Color.white
    static let ink = Color(red: 0.106, green: 0.086, blue: 0.075)      // #1B1613
    static let inkSoft = Color(red: 0.227, green: 0.196, blue: 0.176)  // #3A322D
    static let muted = Color(red: 0.420, green: 0.384, blue: 0.357)    // #6B625B
    static let dot = Color(red: 0.914, green: 0.863, blue: 0.796)      // #E9DCCB
    static let track = Color(red: 0.937, green: 0.894, blue: 0.831)    // #EFE4D4
    static let mint = Color(red: 0.557, green: 0.890, blue: 0.690)     // #8EE3B0
    static let butter = Color(red: 1.0, green: 0.851, blue: 0.4)       // #FFD966
    static let coral = Color(red: 1.0, green: 0.478, blue: 0.4)        // #FF7A66
    static let coralDeep = Color(red: 0.851, green: 0.227, blue: 0.169) // #D93A2B
    static let mintDeep = Color(red: 0.184, green: 0.659, blue: 0.400)  // #2FA866
    static let amber = Color(red: 0.718, green: 0.475, blue: 0.122)     // #B7791F
    static let grape = Color(red: 0.545, green: 0.361, blue: 0.965)    // #8B5CF6
    static let sky = Color(red: 0.561, green: 0.827, blue: 1.0)        // #8FD3FF
    static let coralSoft = Color(red: 1.0, green: 0.882, blue: 0.855)  // #FFE1DA
    static let mintSoft = Color(red: 0.867, green: 0.965, blue: 0.906) // #DDF6E7

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: [Self.cream, Self.cream], startPoint: .top, endPoint: .bottom)
    }

    public var showBackgroundOrbs: Bool { false }

    /// The dot grid of the paper.
    @MainActor public var overlayView: AnyView? {
        AnyView(PopDotGrid().allowsHitTesting(false))
    }

    // MARK: - Cards & Outlines

    public var cardGradient: LinearGradient {
        LinearGradient(colors: [Self.paper, Self.paper], startPoint: .top, endPoint: .bottom)
    }

    public var glassBackground: Color { Self.paper }
    public var glassBorder: Color { Self.ink }
    public var glassHighlight: Color { .clear }
    public var cardCornerRadius: CGFloat { 16 }
    public var pillCornerRadius: CGFloat { 999 }
    public var cardBorderWidth: CGFloat { 2.5 }
    public var cardShadow: ThemeShadow? { ThemeShadow(color: Self.ink, x: 4, y: 4) }

    // MARK: - Typography

    public var textPrimary: Color { Self.ink }
    public var textSecondary: Color { Self.inkSoft }
    public var textTertiary: Color { Self.muted }
    public var fontDesign: Font.Design { .rounded }
    public var displayFontName: String? { PopFonts.display }

    // MARK: - Status

    public var statusHealthy: Color { Self.mint }
    public var statusWarning: Color { Self.butter }
    public var statusCritical: Color { Self.coral }
    public var statusDepleted: Color { Self.coralDeep }
    /// Ink reads on every candy colour; white wouldn't on mint or butter.
    public var textOnStatus: Color { Self.ink }

    /// Candy pastels vanish on a light menu bar: there, deeper versions.
    public func menuBarStatusColor(for status: QuotaStatus, darkMenuBar: Bool) -> Color {
        guard !darkMenuBar else { return statusColor(for: status) }
        return switch status {
        case .healthy: Self.mintDeep
        case .warning: Self.amber
        case .critical, .depleted: Self.coralDeep
        }
    }

    // MARK: - Accents (flat: Pop has no gradients)

    public var accentPrimary: Color { Self.grape }
    public var accentSecondary: Color { Self.sky }

    public var accentGradient: LinearGradient {
        LinearGradient(colors: [Self.grape, Self.grape], startPoint: .leading, endPoint: .trailing)
    }

    public var pillGradient: LinearGradient {
        LinearGradient(colors: [Self.ink, Self.ink], startPoint: .leading, endPoint: .trailing)
    }

    public var shareGradient: LinearGradient {
        LinearGradient(colors: [Self.mint, Self.mint], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Interaction

    public var hoverOverlay: Color { Self.ink.opacity(0.06) }
    public var pressedOverlay: Color { Self.ink.opacity(0.12) }

    // MARK: - Progress

    public var progressTrack: Color { Self.track }

    /// A bar is one flat candy colour for its status, never a blend.
    public func progressGradient(for percent: Double) -> LinearGradient {
        let color: Color = switch percent {
        case ..<20: Self.coral
        case ..<50: Self.butter
        default: Self.mint
        }
        return LinearGradient(colors: [color, color], startPoint: .leading, endPoint: .trailing)
    }

    public init() {}
}

// MARK: - Paper

/// Cream paper's dot grid, drawn once.
struct PopDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(PopTheme.dot))
                    x += spacing
                }
                y += spacing
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Fonts

/// Lilita One (SIL Open Font License, Resources/Fonts), registered for this
/// process the first time Pop asks for it. `nil` if it can't be — the
/// system font stands in.
enum PopFonts {
    static let display: String? = {
        guard let url = Bundle.main.url(forResource: "LilitaOne-Regular", withExtension: "ttf") else { return nil }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered is fine; anything else falls back.
            let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
            if code != CTFontManagerError.alreadyRegistered.rawValue { return nil }
        }
        return "LilitaOne"
    }()
}
