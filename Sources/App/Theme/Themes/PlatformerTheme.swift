import SwiftUI
import Domain

// MARK: - Platformer Theme

/// A Super Mario–style 8-bit theme: blue sky, pixel clouds and hills on a
/// brick floor, ink outlines with hard shadows, quota bars as a row of
/// blocks, big numbers and badges in Press Start 2P, and every other word
/// in Pixelify Sans. A low quota says HURRY UP!,
/// an empty one GAME OVER. The pixel art is ClaudeBar's own.
/// Design: design-concept/platformer-theme/index.html.
public struct PlatformerTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "platformer"
    public let displayName = "Platformer"
    public let icon = "gamecontroller.fill"
    public let subtitle: String? = "8-bit"

    // MARK: - Palette

    static let sky = Color(red: 0.361, green: 0.580, blue: 0.988)       // #5C94FC
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.078)       // #141414
    static let inkSoft = Color(red: 0.165, green: 0.165, blue: 0.165)   // #2A2A2A
    static let navy = Color(red: 0.145, green: 0.227, blue: 0.369)      // #253A5E
    static let paper = Color(red: 1.0, green: 0.973, blue: 0.906)       // #FFF8E7
    static let paperDeep = Color(red: 0.988, green: 0.914, blue: 0.753) // #FCE9C0
    static let cloud = Color.white
    static let cloudShade = Color(red: 0.659, green: 0.847, blue: 1.0)  // #A8D8FF
    static let pipe = Color(red: 0.502, green: 0.816, blue: 0.063)      // #80D010
    static let pipeDeep = Color(red: 0.0, green: 0.659, blue: 0.0)      // #00A800
    static let hill = Color(red: 0.247, green: 0.659, blue: 0.196)      // #3FA832
    static let coin = Color(red: 1.0, green: 0.831, blue: 0.231)        // #FFD43B
    static let block = Color(red: 0.980, green: 0.690, blue: 0.020)     // #FAB005
    static let blockDeep = Color(red: 0.659, green: 0.392, blue: 0.0)   // #A86400
    static let fire = Color(red: 0.988, green: 0.455, blue: 0.376)      // #FC7460
    static let fireDeep = Color(red: 0.894, green: 0.0, blue: 0.345)    // #E40058
    static let stone = Color(red: 0.420, green: 0.420, blue: 0.420)     // #6B6B6B
    static let brick = Color(red: 0.784, green: 0.298, blue: 0.047)     // #C84C0C
    static let brickLight = Color(red: 0.941, green: 0.627, blue: 0.439) // #F0A070
    static let clay = Color(red: 0.910, green: 0.455, blue: 0.227)      // #E8743A, the runner
    static let clayLight = Color(red: 0.965, green: 0.635, blue: 0.431) // #F6A26E

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: [Self.sky, Self.sky], startPoint: .top, endPoint: .bottom)
    }

    public var showBackgroundOrbs: Bool { false }

    /// Clouds in the sky, hills on a brick floor.
    @MainActor public var overlayView: AnyView? {
        AnyView(PlatformerScenery().allowsHitTesting(false))
    }

    // MARK: - Cards & Outlines

    public var cardGradient: LinearGradient {
        LinearGradient(colors: [Self.paper, Self.paper], startPoint: .top, endPoint: .bottom)
    }

    public var glassBackground: Color { Self.paper }
    public var glassBorder: Color { Self.ink }
    public var glassHighlight: Color { .clear }
    /// Square, like blocks.
    public var cardCornerRadius: CGFloat { 4 }
    /// Pills, tabs and badges are square blocks too.
    public var pillCornerRadius: CGFloat { 3 }
    public var cardBorderWidth: CGFloat { 3 }
    public var cardShadow: ThemeShadow? { ThemeShadow(color: Self.ink, x: 4, y: 4) }

    // MARK: - Typography

    public var textPrimary: Color { Self.ink }
    public var textSecondary: Color { Self.inkSoft }
    /// Navy reads on the paper cards and on the sky behind them.
    public var textTertiary: Color { Self.navy }
    public var fontDesign: Font.Design { .rounded }
    /// Pixel text: every word in Pixelify Sans, in four weights. Classic:
    /// plain words.
    public var customFontName: String? { textStyle == .themed ? PlatformerFonts.body : nil }
    public var textStyleName: String? { "Pixel" }
    public func styled(_ style: ThemeTextStyle) -> any AppThemeProvider { PlatformerTheme(textStyle: style, showsRunner: showsRunner) }
    /// Pixel text: big numbers in Press Start 2P. Classic: no pixel face at
    /// all — bold outlined numbers in the system font.
    public var displayFontName: String? { textStyle == .themed ? PlatformerFonts.display : nil }
    /// Press Start 2P is half again as wide as Lilita One.
    public var displayFontScale: CGFloat { 0.6 }
    public var tagline: String? { "Your quotas, one level at a time" }

    // MARK: - Status

    public var statusHealthy: Color { Self.pipe }
    public var statusWarning: Color { Self.coin }
    public var statusCritical: Color { Self.fire }
    public var statusDepleted: Color { Self.stone }
    public var textOnStatus: Color { Self.ink }

    /// Pixel text: badges in the score-line face, a step smaller (it's
    /// wide). Classic: a small bold monospace, like a game's printout.
    public func badgeFont(size: CGFloat) -> Font {
        guard textStyle == .themed, let display = PlatformerFonts.display else {
            return .system(size: size, weight: .bold, design: .monospaced)
        }
        return .custom(display, size: size * 0.8)
    }

    public func statusWord(for status: QuotaStatus) -> String {
        switch status {
        case .critical: "HURRY UP!"
        case .depleted: "GAME OVER"
        case .healthy, .warning: status.badgeText
        }
    }

    /// Bright greens and golds vanish on a light menu bar: there, deeper ones.
    public func menuBarStatusColor(for status: QuotaStatus, darkMenuBar: Bool) -> Color {
        guard !darkMenuBar else { return statusColor(for: status) }
        return switch status {
        case .healthy: Self.pipeDeep
        case .warning: Self.blockDeep
        case .critical, .depleted: Self.fireDeep
        }
    }

    // MARK: - Accents (flat: pixels have no gradients)

    public var accentPrimary: Color { Self.block }
    public var accentSecondary: Color { Self.pipe }

    /// The selected tab is a pipe-green block.
    public var accentGradient: LinearGradient {
        LinearGradient(colors: [Self.pipe, Self.pipe], startPoint: .leading, endPoint: .trailing)
    }

    public var pillGradient: LinearGradient {
        LinearGradient(colors: [Self.ink, Self.ink], startPoint: .leading, endPoint: .trailing)
    }

    public var shareGradient: LinearGradient {
        LinearGradient(colors: [Self.pipe, Self.pipe], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Interaction

    public var hoverOverlay: Color { Self.ink.opacity(0.06) }
    public var pressedOverlay: Color { Self.ink.opacity(0.12) }

    // MARK: - Progress

    public var progressTrack: Color { Self.paperDeep }
    public var progressStyle: ProgressStyle { .blocks(10) }

    // MARK: - The Level

    /// Square buttons and pickers, like blocks.
    public var controlCornerRadius: CGFloat? { 3 }
    /// Two rows of bricks; the action bar stands on them.
    public var groundHeight: CGFloat { PlatformerScenery.floorHeight }
    /// A score line across the top, a ? block to refresh.
    public var headerStyle: HeaderStyle { .scoreLine }
    /// A box-bot strolls the floor while all is well, runs when time runs
    /// low, and falls in a pit at GAME OVER.
    public var runner: GroundRunner? { showsRunner ? PlatformerRunner.runner : nil }
    public func walking(_ shown: Bool) -> any AppThemeProvider { PlatformerTheme(textStyle: textStyle, showsRunner: shown) }
    /// HURRY UP! blinks, as the music speeds up when time runs low.
    public func blinks(_ status: QuotaStatus) -> Bool { status == .critical }
    /// Ink on the green of the selected tab.
    public var textOnAccent: Color { Self.ink }
    /// Badges are square blocks.
    public var badgeCornerRadius: CGFloat? { 0 }
    /// Four rivets hold each card on, like a block's corners.
    public var cardRivetSize: CGFloat? { 4 }

    /// One flat colour for the status, never a blend.
    public func progressGradient(for percent: Double) -> LinearGradient {
        let color: Color = switch percent {
        case ..<20: Self.fire
        case ..<50: Self.coin
        default: Self.pipe
        }
        return LinearGradient(colors: [color, color], startPoint: .leading, endPoint: .trailing)
    }

    public let textStyle: ThemeTextStyle
    /// The person can take the runner off the floor.
    public let showsRunner: Bool

    public init(textStyle: ThemeTextStyle = .themed, showsRunner: Bool = true) {
        self.textStyle = textStyle
        self.showsRunner = showsRunner
    }
}

// MARK: - Scenery

/// The level behind the popover: two clouds, one under the score line and
/// one beside the cards; two hills on the brick floor in the gap the
/// action bar leaves between Dashboard and the icon buttons. Drawn in
/// 3-point art pixels.
struct PlatformerScenery: View {
    private static let px: CGFloat = 3
    static let floorHeight: CGFloat = px * 12

    var body: some View {
        Canvas { context, size in
            let floorHeight = Self.floorHeight
            // As the design has them: a small one under the score line, left
            // of the ? block; a big one in the open sky beside the cards.
            drawCloud(in: &context, at: CGPoint(x: size.width - 118, y: 64), scale: 0.67)
            drawCloud(in: &context, at: CGPoint(x: size.width - 104, y: 380), scale: 1)
            drawHill(in: &context, left: size.width * 0.34, floor: size.height - floorHeight, columns: 30, rows: 15)
            drawHill(in: &context, left: size.width * 0.34 + 84, floor: size.height - floorHeight, columns: 14, rows: 6)
            drawBricks(in: &context, size: size, height: floorHeight)
        }
        .ignoresSafeArea()
    }

    /// Fills art-pixel rectangles `(x, y, width, height)` from `origin`.
    private func fill(_ rects: [(CGFloat, CGFloat, CGFloat, CGFloat)], _ color: Color,
                      at origin: CGPoint, unit: CGFloat, in context: inout GraphicsContext) {
        for (x, y, w, h) in rects {
            let rect = CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: w * unit, height: h * unit)
            context.fill(Path(rect), with: .color(color))
        }
    }

    private func drawCloud(in context: inout GraphicsContext, at origin: CGPoint, scale: CGFloat) {
        let unit = (Self.px * scale).rounded()
        fill([(8, 0, 8, 3), (4, 3, 16, 3), (1, 5, 22, 4)], PlatformerTheme.ink, at: origin, unit: unit, in: &context)
        fill([(9, 1, 6, 3), (5, 4, 14, 3), (2, 6, 20, 2)], PlatformerTheme.cloud, at: origin, unit: unit, in: &context)
        fill([(2, 7, 20, 1)], PlatformerTheme.cloudShade, at: origin, unit: unit, in: &context)
    }

    /// A stepped hill `columns` wide and `rows` tall, standing on `floor`.
    private func drawHill(in context: inout GraphicsContext, left: CGFloat, floor: CGFloat, columns: CGFloat, rows: CGFloat) {
        let unit = Self.px
        let origin = CGPoint(x: left, y: floor - rows * unit)
        var outline: [(CGFloat, CGFloat, CGFloat, CGFloat)] = []
        var face: [(CGFloat, CGFloat, CGFloat, CGFloat)] = []
        let steps: CGFloat = 4
        let stepHeight = rows / steps
        for step in 0..<Int(steps) {
            let inset = (steps - 1 - CGFloat(step)) * columns / 8
            let y = CGFloat(step) * stepHeight
            outline.append((inset, y, columns - 2 * inset, rows - y))
            face.append((inset + 1, y + 1, columns - 2 * inset - 2, rows - y - 1))
        }
        fill(outline, PlatformerTheme.ink, at: origin, unit: unit, in: &context)
        fill(face, PlatformerTheme.hill, at: origin, unit: unit, in: &context)
    }

    /// Two rows of bricks, the second offset by half a brick.
    private func drawBricks(in context: inout GraphicsContext, size: CGSize, height: CGFloat) {
        let top = size.height - height
        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: height)), with: .color(PlatformerTheme.ink))
        let brickWidth: CGFloat = 36, brickHeight = height / 2, mortar = Self.px
        for row in 0..<2 {
            let y = top + CGFloat(row) * brickHeight + mortar
            var x: CGFloat = row == 0 ? 0 : -brickWidth / 2
            while x < size.width {
                let brick = CGRect(x: x + mortar, y: y, width: brickWidth - mortar, height: brickHeight - mortar)
                context.fill(Path(brick), with: .color(PlatformerTheme.brick))
                context.fill(Path(CGRect(x: brick.minX, y: brick.minY, width: brick.width, height: mortar)),
                             with: .color(PlatformerTheme.brickLight))
                x += brickWidth
            }
        }
    }
}

// MARK: - Runner

/// Platformer's runner: an 8×9 box-bot with an antenna, in 3-point art
/// pixels, the same as the scenery's.
enum PlatformerRunner {
    static let runner = GroundRunner(
        laneHeight: 48,
        pixel: 3,
        sprite: RunnerSprite(
            body: ["....K...",
                   "....I...",
                   ".IIIIII.",
                   "IHHOOOOI",
                   "IOOIOOIO",
                   "IOOOOOOI",
                   ".IIIIII."],
            strides: [[".II..II.", ".I....I."],
                      ["..IIII..", "..I..I.."]],
            leap: ["II....II", "I......I"],
            coin: [".III.", "IKKKI", "IKDKI", "IKDKI", "IKDKI", "IKKKI", ".III."],
            palette: ["I": PlatformerTheme.ink, "O": PlatformerTheme.clay, "H": PlatformerTheme.clayLight,
                      "K": PlatformerTheme.coin, "D": PlatformerTheme.blockDeep],
            sweat: PlatformerTheme.cloudShade
        ),
        paces: [.healthy: .stroll, .warning: .walk, .critical: .run, .depleted: .fall]
    )
}

// MARK: - Fonts

/// Press Start 2P (SIL Open Font License, Resources/Fonts). `nil` if it
/// can't be registered — the system font stands in.
enum PlatformerFonts {
    static let display: String? = BundledFont.register(file: "PressStart2P-Regular", name: "PressStart2P-Regular")
    /// Pixelify Sans (SIL Open Font License), one variable font whose named
    /// weights `theme.font` asks for as PixelifySans-Regular, -Bold, …
    static let body: String? = BundledFont.register(file: "PixelifySans", name: "PixelifySans")
}
