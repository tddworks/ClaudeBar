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
// These delegate to the provider's visual identity, eliminating hardcoded switches.

extension AppTheme {
    /// Get provider theme color by ID (delegates to provider's visual identity)
    static func providerColor(for providerId: String, scheme: ColorScheme) -> Color {
        AIProviderRegistry.shared.provider(for: providerId)?
            .themeColorOrDefault(for: scheme) ?? purpleVibrant(for: scheme)
    }

    /// Get provider gradient by ID (delegates to provider's visual identity)
    static func providerGradient(for providerId: String, scheme: ColorScheme) -> LinearGradient {
        AIProviderRegistry.shared.provider(for: providerId)?
            .themeGradientOrDefault(for: scheme) ?? accentGradient(for: scheme)
    }

    /// Get provider icon asset name by ID (delegates to provider's visual identity)
    static func providerIconAssetName(for providerId: String) -> String {
        AIProviderRegistry.shared.provider(for: providerId)?
            .iconAssetNameOrDefault ?? "QuestionIcon"
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
            .environment(\.activeTheme, effectiveColorScheme)
            .environment(\.isChristmasTheme, themeMode.isChristmas)
            .preferredColorScheme(
                themeMode == .system ? nil :
                (themeMode == .light ? .light : .dark)  // Christmas and dark both use .dark
            )
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

// MARK: - Snowfall Effect

struct SnowflakeView: View {
    let size: CGFloat
    let startX: CGFloat
    let startY: CGFloat
    let duration: Double
    let delay: Double

    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var glowOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Glow effect behind snowflake
            Image(systemName: "snowflake")
                .font(.system(size: size * 1.5))
                .foregroundStyle(AppTheme.christmasSnow.opacity(glowOpacity * 0.3))
                .blur(radius: 3)

            // Main snowflake
            Image(systemName: "snowflake")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(AppTheme.christmasSnow.opacity(glowOpacity))
        }
        .rotationEffect(.degrees(rotation))
        .position(x: startX + xOffset, y: startY + yOffset)
        .onAppear {
            // Falling animation
            withAnimation(
                .linear(duration: duration)
                .delay(delay)
                .repeatForever(autoreverses: false)
            ) {
                yOffset = 700
                xOffset = CGFloat.random(in: -40...40)
            }

            // Rotation animation
            withAnimation(
                .linear(duration: duration * 0.4)
                .delay(delay)
                .repeatForever(autoreverses: true)
            ) {
                rotation = Double.random(in: -360...360)
            }

            // Twinkle effect
            withAnimation(
                .easeInOut(duration: 1.5)
                .delay(delay)
                .repeatForever(autoreverses: true)
            ) {
                glowOpacity = Double.random(in: 0.4...1.0)
            }
        }
    }
}

struct SnowfallOverlay: View {
    let snowflakeCount: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Background snowflakes (smaller, slower)
                ForEach(0..<snowflakeCount, id: \.self) { i in
                    SnowflakeView(
                        size: CGFloat.random(in: 6...12),
                        startX: CGFloat.random(in: 0...geo.size.width),
                        startY: CGFloat.random(in: -100...0),
                        duration: Double.random(in: 6...10),
                        delay: Double(i) * 0.15
                    )
                }

                // Layer 2: Foreground snowflakes (larger, faster)
                ForEach(0..<(snowflakeCount / 2), id: \.self) { i in
                    SnowflakeView(
                        size: CGFloat.random(in: 10...16),
                        startX: CGFloat.random(in: 0...geo.size.width),
                        startY: CGFloat.random(in: -80...0),
                        duration: Double.random(in: 4...7),
                        delay: Double(i) * 0.2 + 0.5
                    )
                }

                // Layer 3: Sparkle dots (tiny, scattered)
                ForEach(0..<(snowflakeCount / 3), id: \.self) { i in
                    Circle()
                        .fill(AppTheme.christmasSnow.opacity(Double.random(in: 0.3...0.7)))
                        .frame(width: CGFloat.random(in: 2...4), height: CGFloat.random(in: 2...4))
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                        .blur(radius: 0.5)
                }
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
