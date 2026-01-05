import SwiftUI
import Domain

// MARK: - Theme Mode

/// The active theme mode for the application
enum ThemeMode: String, CaseIterable {
    case light
    case dark
    case system
    case christmas

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        case .christmas: "Christmas"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .system: "circle.lefthalf.filled"
        case .christmas: "snowflake"
        }
    }

    /// Whether this theme uses Christmas-specific colors
    var isChristmas: Bool {
        self == .christmas
    }
}

// MARK: - Theme Environment Keys

private struct ActiveThemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .dark
}

private struct IsChristmasThemeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var activeTheme: ColorScheme {
        get { self[ActiveThemeKey.self] }
        set { self[ActiveThemeKey.self] = newValue }
    }

    var isChristmasTheme: Bool {
        get { self[IsChristmasThemeKey.self] }
        set { self[IsChristmasThemeKey.self] = newValue }
    }
}

// MARK: - ClaudeBar App Theme
// Adaptive purple-pink gradients with glassmorphism
// Distinct aesthetics for light and dark modes

enum AppTheme {

    // MARK: - Core Colors (Adaptive)

    /// Deep purple base - darker in dark mode, richer in light
    static func purpleDeep(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.38, green: 0.22, blue: 0.72)
            : Color(red: 0.45, green: 0.28, blue: 0.78)
    }

    /// Vibrant purple
    static func purpleVibrant(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.55, green: 0.32, blue: 0.85)
            : Color(red: 0.62, green: 0.42, blue: 0.92)
    }

    /// Hot pink accent
    static func pinkHot(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.85, green: 0.35, blue: 0.65)
            : Color(red: 0.92, green: 0.45, blue: 0.72)
    }

    /// Soft magenta
    static func magentaSoft(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.78, green: 0.42, blue: 0.75)
            : Color(red: 0.85, green: 0.52, blue: 0.82)
    }

    /// Electric violet
    static func violetElectric(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.62, green: 0.28, blue: 0.98)
            : Color(red: 0.72, green: 0.42, blue: 1.0)
    }

    // MARK: - Accent Colors (Adaptive)

    /// Coral accent for highlights
    static func coralAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.55, blue: 0.45)
            : Color(red: 0.95, green: 0.48, blue: 0.38)
    }

    /// Golden accent
    static func goldenGlow(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.78, blue: 0.35)
            : Color(red: 0.92, green: 0.72, blue: 0.28)
    }

    /// Teal accent
    static func tealBright(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.35, green: 0.85, blue: 0.78)
            : Color(red: 0.18, green: 0.72, blue: 0.68)
    }

    // MARK: - Christmas Theme Colors
    // Design: "Vibrant American Christmas" - bold red & green with sparkly gold
    // Deep neutral background lets vibrant colors POP without blending into mud

    /// Christmas black - deep neutral background (lets colors pop)
    static let christmasBlack = Color(red: 0.06, green: 0.06, blue: 0.08)

    /// Christmas charcoal - secondary background
    static let christmasCharcoal = Color(red: 0.10, green: 0.10, blue: 0.12)

    /// Vibrant candy red - bright, saturated holiday red
    static let christmasRed = Color(red: 0.92, green: 0.12, blue: 0.15)

    /// Deep crimson - darker red accent
    static let christmasCrimson = Color(red: 0.70, green: 0.08, blue: 0.12)

    /// Vibrant holly green - bright, saturated green
    static let christmasGreen = Color(red: 0.10, green: 0.72, blue: 0.32)

    /// Deep forest green - darker green accent
    static let christmasForest = Color(red: 0.05, green: 0.45, blue: 0.20)

    /// Sparkle gold - bright festive gold
    static let christmasGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    /// Warm gold - slightly darker gold
    static let christmasGoldWarm = Color(red: 0.95, green: 0.70, blue: 0.15)

    /// Snow white - pure white
    static let christmasSnow = Color.white

    /// Silver sparkle - cool accent
    static let christmasSilver = Color(red: 0.85, green: 0.88, blue: 0.92)

    // MARK: - Christmas Gradients

    /// Christmas background - deep with visible red/green zones
    static let christmasBackgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.05, blue: 0.08),  // deep red tint top
            christmasCharcoal,
            Color(red: 0.05, green: 0.18, blue: 0.10)   // deep green tint bottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Christmas card gradient - dark glass with subtle gold shimmer
    static let christmasCardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            christmasGold.opacity(0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Christmas accent gradient - red to gold (festive!)
    static let christmasAccentGradient = LinearGradient(
        colors: [christmasRed, christmasGold],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Christmas green gradient - for buttons
    static let christmasGreenGradient = LinearGradient(
        colors: [christmasGreen, christmasForest],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Christmas red gradient - for buttons
    static let christmasRedGradient = LinearGradient(
        colors: [christmasRed, christmasCrimson],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Christmas gold gradient - for share button
    static let christmasGoldGradient = LinearGradient(
        colors: [christmasGold, christmasGoldWarm],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Christmas pill gradient - subtle red/green shimmer
    static let christmasPillGradient = LinearGradient(
        colors: [
            christmasRed.opacity(0.3),
            christmasGreen.opacity(0.2)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Christmas glass background
    static let christmasGlassBackground = Color.white.opacity(0.10)

    /// Christmas glass border - festive gold/red mix
    static let christmasGlassBorder = christmasGold.opacity(0.6)

    /// Christmas glass highlight - bright gold sparkle
    static let christmasGlassHighlight = christmasGold.opacity(0.7)

    /// Christmas text primary - pure white
    static let christmasTextPrimary = christmasSnow

    /// Christmas text secondary - softer white
    static let christmasTextSecondary = christmasSnow.opacity(0.85)

    /// Christmas text tertiary - muted
    static let christmasTextTertiary = christmasSnow.opacity(0.6)

    // MARK: - Legacy Static Colors (for backward compatibility)

    static let purpleDeep = Color(red: 0.38, green: 0.22, blue: 0.72)
    static let purpleVibrant = Color(red: 0.55, green: 0.32, blue: 0.85)
    static let pinkHot = Color(red: 0.85, green: 0.35, blue: 0.65)
    static let magentaSoft = Color(red: 0.78, green: 0.42, blue: 0.75)
    static let violetElectric = Color(red: 0.62, green: 0.28, blue: 0.98)
    static let coralAccent = Color(red: 0.98, green: 0.55, blue: 0.45)
    static let goldenGlow = Color(red: 0.98, green: 0.78, blue: 0.35)
    static let tealBright = Color(red: 0.35, green: 0.85, blue: 0.78)

    // MARK: - Status Colors (Adaptive)

    static func statusHealthy(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.35, green: 0.92, blue: 0.68)
            : Color(red: 0.15, green: 0.72, blue: 0.52)
    }

    static func statusWarning(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.72, blue: 0.35)
            : Color(red: 0.88, green: 0.58, blue: 0.18)
    }

    static func statusCritical(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.98, green: 0.42, blue: 0.52)
            : Color(red: 0.88, green: 0.28, blue: 0.38)
    }

    static func statusDepleted(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.85, green: 0.25, blue: 0.35)
            : Color(red: 0.75, green: 0.18, blue: 0.28)
    }

    // Legacy static status colors
    static let statusHealthy = Color(red: 0.35, green: 0.92, blue: 0.68)
    static let statusWarning = Color(red: 0.98, green: 0.72, blue: 0.35)
    static let statusCritical = Color(red: 0.98, green: 0.42, blue: 0.52)
    static let statusDepleted = Color(red: 0.85, green: 0.25, blue: 0.35)

    // MARK: - Text Colors

    /// Primary text color
    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.12, green: 0.08, blue: 0.22)
    }

    /// Secondary text color
    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? .white.opacity(0.7)
            : Color(red: 0.35, green: 0.28, blue: 0.45).opacity(0.85)
    }

    /// Tertiary/muted text
    static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? .white.opacity(0.5)
            : Color(red: 0.45, green: 0.38, blue: 0.55).opacity(0.7)
    }

    // MARK: - Gradients (Adaptive)

    /// Main background gradient
    static func backgroundGradient(for scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [
                    purpleDeep(for: scheme),
                    purpleVibrant(for: scheme),
                    pinkHot(for: scheme).opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 1.0),
                    Color(red: 0.95, green: 0.92, blue: 0.98),
                    Color(red: 0.98, green: 0.94, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    /// Card background gradient
    static func cardGradient(for scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color.white.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    /// Accent gradient for highlights
    static func accentGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [coralAccent(for: scheme), pinkHot(for: scheme)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Share button gradient - warm gold/amber tones
    static func shareGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.75, blue: 0.0),  // Golden yellow
                Color(red: 1.0, green: 0.55, blue: 0.0)   // Orange
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Provider pill gradient
    static func pillGradient(for scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [
                    magentaSoft(for: scheme).opacity(0.6),
                    pinkHot(for: scheme).opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [
                    purpleVibrant(for: scheme).opacity(0.15),
                    pinkHot(for: scheme).opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    /// Progress bar gradient based on percentage
    static func progressGradient(for percent: Double, scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = switch percent {
        case 0..<20:
            [statusCritical(for: scheme), statusDepleted(for: scheme)]
        case 20..<50:
            [statusWarning(for: scheme), coralAccent(for: scheme)]
        default:
            [tealBright(for: scheme), statusHealthy(for: scheme)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    // Legacy static gradients
    static let backgroundGradient = LinearGradient(
        colors: [purpleDeep, purpleVibrant, pinkHot.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [coralAccent, pinkHot],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let pillGradient = LinearGradient(
        colors: [magentaSoft.opacity(0.6), pinkHot.opacity(0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func progressGradient(for percent: Double) -> LinearGradient {
        let colors: [Color] = switch percent {
        case 0..<20:
            [statusCritical, statusDepleted]
        case 20..<50:
            [statusWarning, coralAccent]
        default:
            [tealBright, statusHealthy]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Glass Effect Colors (Adaptive)

    static func glassBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.04)
    }

    static func glassBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.25)
            : purpleVibrant(for: scheme).opacity(0.18)
    }

    static func glassHighlight(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.35)
            : Color.white.opacity(0.95)
    }

    static func glassShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.3)
            : purpleDeep(for: scheme).opacity(0.12)
    }

    // Legacy static glass colors
    static let glassBackground = Color.white.opacity(0.12)
    static let glassBorder = Color.white.opacity(0.25)
    static let glassHighlight = Color.white.opacity(0.35)

    // MARK: - Interactive State Colors

    static func hoverOverlay(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : purpleVibrant(for: scheme).opacity(0.08)
    }

    static func pressedOverlay(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : purpleVibrant(for: scheme).opacity(0.15)
    }

    // MARK: - Typography

    /// Large stat number font
    static func statFont(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Title font
    static func titleFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Body text font
    static func bodyFont(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    /// Caption font
    static func captionFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK: - Adaptive Glass Card Modifier

struct AdaptiveGlassCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base glass layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(AppTheme.cardGradient(for: colorScheme))

                    // Shadow for light mode depth
                    if colorScheme == .light {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clear)
                            .shadow(
                                color: AppTheme.glassShadow(for: colorScheme),
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    }

                    // Inner border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(AppTheme.glassBorder(for: colorScheme), lineWidth: 1)

                    // Top edge shine
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppTheme.glassHighlight(for: colorScheme),
                                    Color.clear,
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

// MARK: - Glass Card Modifier (Legacy - uses adaptive internally)

struct GlassCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .modifier(AdaptiveGlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 12) -> some View {
        modifier(GlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }

    func adaptiveGlassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 12) -> some View {
        modifier(AdaptiveGlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Shimmer Animation Modifier (Adaptive)

struct ShimmerEffect: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        let shimmerColor = colorScheme == .dark
            ? Color.white
            : AppTheme.purpleVibrant(for: colorScheme)

        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            shimmerColor.opacity(0),
                            shimmerColor.opacity(0.15),
                            shimmerColor.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5 - geo.size.width * 0.25)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Glow Effect Modifier (Adaptive)

struct GlowEffect: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        let intensity = colorScheme == .dark ? 1.0 : 0.6
        content
            .shadow(color: color.opacity(0.5 * intensity), radius: radius / 2)
            .shadow(color: color.opacity(0.3 * intensity), radius: radius)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}

// MARK: - Badge Style (Adaptive)

struct BadgeStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(AppTheme.captionFont(size: 8))
            .foregroundStyle(colorScheme == .dark ? .white : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(colorScheme == .dark ? 0.9 : 0.85))
                    .shadow(
                        color: colorScheme == .light ? color.opacity(0.3) : .clear,
                        radius: 2,
                        y: 1
                    )
            )
            .fixedSize()
    }
}

extension View {
    func badge(_ color: Color) -> some View {
        modifier(BadgeStyle(color: color))
    }
}

// MARK: - Adaptive Text Style Modifier

struct AdaptiveTextStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let style: TextStyle

    enum TextStyle {
        case primary
        case secondary
        case tertiary
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(color)
    }

    private var color: Color {
        switch style {
        case .primary:
            AppTheme.textPrimary(for: colorScheme)
        case .secondary:
            AppTheme.textSecondary(for: colorScheme)
        case .tertiary:
            AppTheme.textTertiary(for: colorScheme)
        }
    }
}

extension View {
    func adaptiveText(_ style: AdaptiveTextStyle.TextStyle = .primary) -> some View {
        modifier(AdaptiveTextStyle(style: style))
    }
}

// MARK: - Provider Colors (by ID)
// Static visual identity based on provider ID - no registry needed.

extension AppTheme {
    /// Get provider theme color by ID
    static func providerColor(for providerId: String, scheme: ColorScheme) -> Color {
        switch providerId {
        case "claude":
            return coralAccent(for: scheme)
        case "codex":
            return tealBright(for: scheme)
        case "gemini":
            return goldenGlow(for: scheme)
        case "copilot":
            return scheme == .dark
                ? Color(red: 0.38, green: 0.55, blue: 0.93)
                : Color(red: 0.26, green: 0.43, blue: 0.82)
        case "antigravity":
            return scheme == .dark
                ? Color(red: 0.72, green: 0.35, blue: 0.85)
                : Color(red: 0.58, green: 0.22, blue: 0.72)
        case "zai":
            return scheme == .dark
                ? Color(red: 0.35, green: 0.60, blue: 1.0)
                : Color(red: 0.23, green: 0.51, blue: 0.96)
        default:
            return purpleVibrant(for: scheme)
        }
    }

    /// Get provider gradient by ID
    static func providerGradient(for providerId: String, scheme: ColorScheme) -> LinearGradient {
        let primaryColor = providerColor(for: providerId, scheme: scheme)
        let secondaryColor: Color

        switch providerId {
        case "claude":
            secondaryColor = pinkHot(for: scheme)
        case "codex":
            secondaryColor = scheme == .dark
                ? Color(red: 0.25, green: 0.65, blue: 0.85)
                : Color(red: 0.12, green: 0.52, blue: 0.72)
        case "gemini":
            secondaryColor = scheme == .dark
                ? Color(red: 0.95, green: 0.55, blue: 0.35)
                : Color(red: 0.85, green: 0.45, blue: 0.25)
        case "copilot":
            secondaryColor = scheme == .dark
                ? Color(red: 0.55, green: 0.40, blue: 0.90)
                : Color(red: 0.45, green: 0.30, blue: 0.80)
        case "antigravity":
            secondaryColor = scheme == .dark
                ? Color(red: 0.45, green: 0.25, blue: 0.75)
                : Color(red: 0.35, green: 0.15, blue: 0.65)
        case "zai":
            secondaryColor = scheme == .dark
                ? Color(red: 0.30, green: 0.45, blue: 0.85)
                : Color(red: 0.20, green: 0.35, blue: 0.75)
        default:
            return accentGradient(for: scheme)
        }

        return LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Get provider icon asset name by ID
    static func providerIconAssetName(for providerId: String) -> String {
        switch providerId {
        case "claude": return "ClaudeIcon"
        case "codex": return "CodexIcon"
        case "gemini": return "GeminiIcon"
        case "copilot": return "CopilotIcon"
        case "antigravity": return "AntigravityIcon"
        case "zai": return "ZaiIcon"
        default: return "QuestionIcon"
        }
    }

    /// Get provider display name by ID
    static func providerName(for providerId: String) -> String {
        switch providerId {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "copilot": return "GitHub Copilot"
        case "antigravity": return "Antigravity"
        case "zai": return "Z.ai"
        default: return providerId.capitalized
        }
    }

    /// Get provider SF symbol icon by ID
    static func providerSymbolIcon(for providerId: String) -> String {
        switch providerId {
        case "claude": return "brain.fill"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "sparkles"
        case "copilot": return "chevron.left.forwardslash.chevron.right"
        case "antigravity": return "wand.and.stars"
        case "zai": return "z.square.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Status Theme Colors (Adaptive)

extension QuotaStatus {
    func themeColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .healthy:
            AppTheme.statusHealthy(for: scheme)
        case .warning:
            AppTheme.statusWarning(for: scheme)
        case .critical:
            AppTheme.statusCritical(for: scheme)
        case .depleted:
            AppTheme.statusDepleted(for: scheme)
        }
    }

    // Legacy static property
    var themeColor: Color {
        switch self {
        case .healthy:
            AppTheme.statusHealthy
        case .warning:
            AppTheme.statusWarning
        case .critical:
            AppTheme.statusCritical
        case .depleted:
            AppTheme.statusDepleted
        }
    }

    var badgeText: String {
        switch self {
        case .healthy: "HEALTHY"
        case .warning: "WARNING"
        case .critical: "LOW"
        case .depleted: "EMPTY"
        }
    }

    /// Simple display color for status indicators (moved from Domain to keep Domain SwiftUI-free)
    var displayColor: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .critical, .depleted: .red
        }
    }
}

// MARK: - BudgetStatus Theme Extension

extension BudgetStatus {
    /// Returns the theme color for this budget status
    func themeColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .withinBudget:
            AppTheme.statusHealthy(for: scheme)
        case .approachingLimit:
            AppTheme.statusWarning(for: scheme)
        case .overBudget:
            AppTheme.statusCritical(for: scheme)
        }
    }

    /// Legacy static property for backward compatibility
    var themeColor: Color {
        switch self {
        case .withinBudget:
            AppTheme.statusHealthy
        case .approachingLimit:
            AppTheme.statusWarning
        case .overBudget:
            AppTheme.statusCritical
        }
    }

    /// Simple display color for status indicators
    var displayColor: Color {
        switch self {
        case .withinBudget: .green
        case .approachingLimit: .orange
        case .overBudget: .red
        }
    }
}

// MARK: - Theme Switcher Button

struct ThemeSwitcherButton: View {
    @Binding var themeMode: ThemeMode
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                cycleTheme()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(AppTheme.glassBackground(for: colorScheme))
                    .frame(width: 32, height: 32)

                Circle()
                    .stroke(AppTheme.glassBorder(for: colorScheme), lineWidth: 1)
                    .frame(width: 32, height: 32)

                Image(systemName: themeMode.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                    .rotationEffect(.degrees(themeMode == .dark ? -15 : 0))
            }
            .scaleEffect(isHovering ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Theme: \(themeMode.displayName)")
    }

    private func cycleTheme() {
        switch themeMode {
        case .light: themeMode = .dark
        case .dark: themeMode = .system
        case .system: themeMode = .christmas
        case .christmas: themeMode = .light
        }
    }
}

// MARK: - Theme Provider Modifier

struct ThemeProvider: ViewModifier {
    let themeMode: ThemeMode
    @Environment(\.colorScheme) private var systemColorScheme

    private var effectiveColorScheme: ColorScheme {
        switch themeMode {
        case .light: .light
        case .dark: .dark
        case .system: systemColorScheme
        case .christmas: .dark  // Christmas uses dark mode base
        }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, effectiveColorScheme)  // Override colorScheme directly!
            .environment(\.activeTheme, effectiveColorScheme)
            .environment(\.isChristmasTheme, themeMode.isChristmas)
    }
}

extension View {
    func themeProvider(_ mode: ThemeMode) -> some View {
        modifier(ThemeProvider(themeMode: mode))
    }
}

// MARK: - Christmas Glass Card Modifier

struct ChristmasGlassCardStyle: ViewModifier {
    @Environment(\.isChristmasTheme) private var isChristmas
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base glass layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isChristmas ? AppTheme.christmasCardGradient : AppTheme.cardGradient)

                    // Inner border with gold accent for Christmas
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isChristmas ? AppTheme.christmasGlassBorder : AppTheme.glassBorder,
                            lineWidth: 1
                        )

                    // Top edge shine
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    isChristmas ? AppTheme.christmasGlassHighlight : AppTheme.glassHighlight,
                                    Color.clear,
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

extension View {
    func christmasGlassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 12) -> some View {
        modifier(ChristmasGlassCardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Snowfall Effect (Canvas + TimelineView)

/// Pre-computed snowflake properties
private struct Snowflake {
    let size: CGFloat
    let xRatio: CGFloat        // 0-1 position ratio
    let speed: CGFloat         // fall speed multiplier
    let driftAmp: CGFloat      // horizontal drift amplitude
    let driftFreq: CGFloat     // drift frequency
    let driftPhase: CGFloat    // drift phase offset
    let rotationSpeed: CGFloat
    let opacity: Double
    let delay: Double          // stagger start time
    let dismissAt: Double      // 0.5-1.0: when to fade out (1.0 = at bottom)
}

/// Generate snowflakes with seeded random
private func generateSnowflakes(count: Int, seed: Int) -> [Snowflake] {
    srand48(seed)
    return (0..<count).map { i in
        let dismissEarly = drand48() < 0.4  // 40% dismiss early
        return Snowflake(
            size: CGFloat(6 + drand48() * 10),
            xRatio: CGFloat(drand48()),
            speed: CGFloat(0.6 + drand48() * 0.8),
            driftAmp: CGFloat(15 + drand48() * 25),
            driftFreq: CGFloat(0.3 + drand48() * 0.4),
            driftPhase: CGFloat(drand48() * .pi * 2),
            rotationSpeed: CGFloat(20 + drand48() * 40),
            opacity: 0.5 + drand48() * 0.45,
            delay: Double(i) * 0.8,
            dismissAt: dismissEarly ? 0.45 + drand48() * 0.4 : 1.0
        )
    }
}

struct SnowfallOverlay: View {
    let snowflakeCount: Int
    private let snowflakes: [Snowflake]

    init(snowflakeCount: Int) {
        self.snowflakeCount = snowflakeCount
        self.snowflakes = generateSnowflakes(count: min(snowflakeCount, 20), seed: 42)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                guard let symbol = context.resolveSymbol(id: 0) else { return }

                for flake in snowflakes {
                    // Calculate fall progress (loops every ~10 seconds based on speed)
                    let cycleDuration = 10.0 / Double(flake.speed)
                    let t = ((time - flake.delay).truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration

                    // Skip if before delay
                    guard time > flake.delay else { continue }

                    // Ensure t is positive
                    let progress = t < 0 ? t + 1 : t

                    // Y position: fall from top to bottom
                    let y = -30 + progress * (size.height + 60)

                    // X position: base + drift
                    let drift = sin(time * Double(flake.driftFreq) + Double(flake.driftPhase)) * Double(flake.driftAmp)
                    let x = Double(flake.xRatio) * size.width + drift

                    // Rotation
                    let rotation = Angle.degrees(time * Double(flake.rotationSpeed))

                    // Opacity with fade in/out and random dismissal
                    var opacity = flake.opacity

                    // Fade in
                    if progress < 0.1 {
                        opacity *= progress / 0.1
                    }

                    // Fade out at dismissAt point
                    if progress > flake.dismissAt - 0.1 {
                        let fadeProgress = (progress - (flake.dismissAt - 0.1)) / 0.1
                        opacity *= max(0, 1.0 - fadeProgress)
                    }

                    // Skip if invisible
                    guard opacity > 0.02 else { continue }

                    // Draw
                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: rotation)
                    ctx.scaleBy(x: flake.size / 14, y: flake.size / 14)
                    ctx.draw(symbol, at: .zero)
                }
            } symbols: {
                Image(systemName: "snowflake")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(AppTheme.christmasSnow)
                    .tag(0)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Christmas Orbs Background

struct ChristmasBackgroundOrbs: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // BIG VIBRANT RED orb (top left) - very visible!
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.christmasRed.opacity(0.85),
                                AppTheme.christmasRed.opacity(0.5),
                                AppTheme.christmasCrimson.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: -100, y: -100)
                    .blur(radius: 35)

                // BIG VIBRANT GREEN orb (bottom right) - very visible!
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.christmasGreen.opacity(0.8),
                                AppTheme.christmasGreen.opacity(0.45),
                                AppTheme.christmasForest.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 170
                        )
                    )
                    .frame(width: 340, height: 340)
                    .offset(x: geo.size.width - 40, y: geo.size.height - 120)
                    .blur(radius: 30)

                // GOLD sparkle orb (center top) - ties it together
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.christmasGold.opacity(0.7),
                                AppTheme.christmasGoldWarm.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: geo.size.width * 0.5 - 100, y: -20)
                    .blur(radius: 25)

                // Small red accent (right side middle)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.christmasRed.opacity(0.5),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .offset(x: geo.size.width - 80, y: geo.size.height * 0.35)
                    .blur(radius: 20)

                // Small green accent (left side bottom)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.christmasGreen.opacity(0.45),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)
                    .offset(x: 30, y: geo.size.height * 0.7)
                    .blur(radius: 18)
            }
        }
    }
}
