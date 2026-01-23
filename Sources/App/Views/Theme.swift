import SwiftUI
import Domain

// MARK: - Theme Mode

/// The active theme mode for the application
enum ThemeMode: String, CaseIterable {
    case light
    case dark
    case system
    case cli
    case christmas

    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        case .cli: "CLI"
        case .christmas: "Christmas"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .system: "circle.lefthalf.filled"
        case .cli: "terminal.fill"
        case .christmas: "snowflake"
        }
    }

    /// Whether this theme uses Christmas-specific colors
    var isChristmas: Bool {
        self == .christmas
    }

    /// Whether this theme uses CLI-specific colors
    var isCLI: Bool {
        self == .cli
    }
}

// MARK: - Theme Environment Keys

// MARK: - Theme Environment Keys

private struct ThemeModeKey: EnvironmentKey {
    static let defaultValue: ThemeMode = .system
}

extension EnvironmentValues {
    var themeMode: ThemeMode {
        get { self[ThemeModeKey.self] }
        set { self[ThemeModeKey.self] = newValue }
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
        case "bedrock":
            // AWS orange color
            return scheme == .dark
                ? Color(red: 1.0, green: 0.60, blue: 0.20)
                : Color(red: 0.92, green: 0.47, blue: 0.07)
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
        case "bedrock":
            // AWS orange gradient
            secondaryColor = scheme == .dark
                ? Color(red: 0.85, green: 0.40, blue: 0.15)
                : Color(red: 0.75, green: 0.30, blue: 0.05)
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
        case "bedrock": return "BedrockIcon"
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
        case "bedrock": return "AWS Bedrock"
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
        case "bedrock": return "cloud.fill" // AWS cloud icon
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
    /// Maps BudgetStatus to QuotaStatus for theme color lookup
    var toQuotaStatus: QuotaStatus {
        switch self {
        case .withinBudget: .healthy
        case .approachingLimit: .warning
        case .overBudget: .critical
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
        case .system: themeMode = .cli
        case .cli: themeMode = .christmas
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
        case .cli: .dark  // CLI uses dark mode base
        case .christmas: .dark  // Christmas uses dark mode base
        }
    }

    func body(content: Content) -> some View {
        content
        content
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.themeMode, themeMode)
    }
}

extension View {
    func themeProvider(_ mode: ThemeMode) -> some View {
        modifier(ThemeProvider(themeMode: mode))
    }
}




