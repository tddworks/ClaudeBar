import SwiftUI

// MARK: - Christmas Theme

/// Festive holiday theme with red, green, and gold accents.
/// Features snowfall animation overlay and warm holiday colors.
public struct ChristmasTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "christmas"
    public let displayName = "Christmas"
    public let icon = "snowflake"
    public let subtitle: String? = "Festive"
    public let statusBarIconName: String? = "snowflake"

    // MARK: - Christmas-Specific Colors
    
    // Static definitions for reuse in internal views
    static let black = Color(red: 0.08, green: 0.06, blue: 0.10)
    static let red = Color(red: 0.92, green: 0.12, blue: 0.15)
    static let crimson = Color(red: 0.72, green: 0.08, blue: 0.12)
    static let green = Color(red: 0.10, green: 0.72, blue: 0.32)
    static let forest = Color(red: 0.05, green: 0.52, blue: 0.22)
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let goldWarm = Color(red: 0.95, green: 0.70, blue: 0.15)
    static let snow = Color(red: 0.98, green: 0.98, blue: 1.0)
    static let darkGreen = Color(red: 0.12, green: 0.45, blue: 0.28)
    static let charcoal = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let silver = Color(red: 0.85, green: 0.88, blue: 0.92)

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.05, blue: 0.08),  // Deep red tint top
                Self.charcoal,
                Color(red: 0.05, green: 0.18, blue: 0.10)   // Deep green tint bottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { true }

    @MainActor
    public var overlayView: AnyView? {
        AnyView(ChristmasSnowfallOverlay(snowflakeCount: 25))
    }

    // MARK: - Cards & Glass

    public static let cardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            gold.opacity(0.03)  // Subtle gold shimmer
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public var cardGradient: LinearGradient { Self.cardGradient }

    public static let glassBackground = Color.white.opacity(0.10)
    public var glassBackground: Color { Self.glassBackground }

    public static let glassBorder = gold.opacity(0.6)
    public var glassBorder: Color { Self.glassBorder }

    public static let glassHighlight = gold.opacity(0.7)
    public var glassHighlight: Color { Self.glassHighlight }

    public var cardCornerRadius: CGFloat { 14 }
    public var pillCornerRadius: CGFloat { 20 }

    // MARK: - Typography

    public var textPrimary: Color { Self.snow }
    public var textSecondary: Color { Self.snow.opacity(0.85) }
    public var textTertiary: Color { Self.snow.opacity(0.6) }
    public var fontDesign: Font.Design { .rounded }

    // MARK: - Status Colors

    public var statusHealthy: Color { Self.green }
    public var statusWarning: Color { Self.gold }
    public var statusCritical: Color { Self.red }
    public var statusDepleted: Color { Self.red.opacity(0.7) }

    // MARK: - Accents

    public var accentPrimary: Color { Self.red }
    public var accentSecondary: Color { Self.green }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Self.red, Self.gold],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Self.red.opacity(0.3),
                Self.green.opacity(0.2)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [Self.gold, Self.goldWarm],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color { Self.gold.opacity(0.1) }
    public var pressedOverlay: Color { Self.gold.opacity(0.15) }

    // MARK: - Progress Bar

    public var progressTrack: Color { Color.white.opacity(0.15) }

    // MARK: - Initializer

    public init() {}
}

// MARK: - Christmas Snowfall Overlay

/// Snowfall animation overlay for Christmas theme
struct ChristmasSnowfallOverlay: View {
    let snowflakeCount: Int
    
    var body: some View {
        SnowfallOverlay(snowflakeCount: snowflakeCount)
    }
}

// MARK: - Christmas Orbs Background

struct ChristmasBackgroundOrbs: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // BIG VIBRANT RED orb (top left)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ChristmasTheme.red.opacity(0.85),
                                ChristmasTheme.red.opacity(0.5),
                                ChristmasTheme.crimson.opacity(0.2),
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

                // BIG VIBRANT GREEN orb (bottom right)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ChristmasTheme.green.opacity(0.8),
                                ChristmasTheme.green.opacity(0.45),
                                ChristmasTheme.forest.opacity(0.2),
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

                // GOLD sparkle orb (center top)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ChristmasTheme.gold.opacity(0.7),
                                ChristmasTheme.goldWarm.opacity(0.3),
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
                                ChristmasTheme.red.opacity(0.5),
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
                                ChristmasTheme.green.opacity(0.45),
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

// MARK: - Christmas Glass Card Modifier

struct ChristmasGlassCardStyle: ViewModifier {
    @Environment(\.themeMode) private var themeMode
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base glass layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(themeMode.isChristmas ? ChristmasTheme.cardGradient : AppTheme.cardGradient(for: .dark))

                    // Inner border with gold accent for Christmas
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            themeMode.isChristmas ? ChristmasTheme.glassBorder : AppTheme.glassBorder(for: .dark),
                            lineWidth: 1
                        )

                    // Top edge shine
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    themeMode.isChristmas ? ChristmasTheme.glassHighlight : AppTheme.glassHighlight(for: .dark),
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

private struct Snowflake {
    let size: CGFloat
    let xRatio: CGFloat
    let speed: CGFloat
    let driftAmp: CGFloat
    let driftFreq: CGFloat
    let driftPhase: CGFloat
    let rotationSpeed: CGFloat
    let opacity: Double
    let delay: Double
    let dismissAt: Double
}

private func generateSnowflakes(count: Int, seed: Int) -> [Snowflake] {
    srand48(seed)
    return (0..<count).map { i in
        let dismissEarly = drand48() < 0.4
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
                    let cycleDuration = 10.0 / Double(flake.speed)
                    let t = ((time - flake.delay).truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
                    guard time > flake.delay else { continue }
                    let progress = t < 0 ? t + 1 : t
                    let y = -30 + progress * (size.height + 60)
                    let drift = sin(time * Double(flake.driftFreq) + Double(flake.driftPhase)) * Double(flake.driftAmp)
                    let x = Double(flake.xRatio) * size.width + drift
                    let rotation = Angle.degrees(time * Double(flake.rotationSpeed))
                    var opacity = flake.opacity
                    if progress < 0.1 { opacity *= progress / 0.1 }
                    if progress > flake.dismissAt - 0.1 {
                        let fadeProgress = (progress - (flake.dismissAt - 0.1)) / 0.1
                        opacity *= max(0, 1.0 - fadeProgress)
                    }
                    guard opacity > 0.02 else { continue }
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
                    .foregroundColor(ChristmasTheme.snow)
                    .tag(0)
            }
        }
        .allowsHitTesting(false)
    }
}
