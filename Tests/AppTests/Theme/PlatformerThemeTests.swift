import SwiftUI
import Testing
import Kit
@testable import ClaudeBar

/// Platformer: a Super Mario–style 8-bit theme. Blue sky, ink outlines with
/// hard shadows, quota bars as a row of ten blocks, big numbers in a pixel
/// font, and a low or empty quota that says HURRY UP! or GAME OVER.
/// Every other theme keeps its bar, its plain words and its own tagline.
@MainActor
@Suite
struct PlatformerThemeTests {
    @Test func `should offer Platformer among the built-in themes`() {
        #expect(ThemeRegistry.shared.theme(for: "platformer")?.displayName == "Platformer")
        #expect(ThemeMode(rawValue: "platformer") == .platformer)
    }

    @Test func `should outline Platformer's cards in ink with a hard shadow`() {
        let theme = PlatformerTheme()
        #expect(theme.glassBorder == PlatformerTheme.ink)
        #expect(theme.cardShadow == ThemeShadow(color: PlatformerTheme.ink, radius: 0, x: 4, y: 4))
        // Outlined: big numbers print outlined, Settings draws paper.
        #expect(theme.isOutlined)
    }

    @Test func `should draw Platformer's quota bars as a row of ten blocks`() {
        #expect(PlatformerTheme().progressStyle == .blocks(10))
    }

    @Test func `should show Platformer's big numbers in a pixel font`() {
        #expect(PlatformerTheme().displayFontName == "PressStart2P-Regular")
        // Wide pixels print smaller, so "$125.00" fits its card.
        #expect(PlatformerTheme().displayFontScale < 1)
    }

    @Test func `should write every word in a pixel face, with square badges`() {
        let theme = PlatformerTheme()
        #expect(theme.customFontName == "PixelifySans")
        #expect(theme.pillCornerRadius == 3)
    }

    @Test func `should say HURRY UP when a quota runs low and GAME OVER when it is empty`() {
        let theme = PlatformerTheme()
        #expect(theme.statusWord(for: .healthy) == "HEALTHY")
        #expect(theme.statusWord(for: .warning) == "WARNING")
        #expect(theme.statusWord(for: .critical) == "HURRY UP!")
        #expect(theme.statusWord(for: .depleted) == "GAME OVER")
    }

    @Test func `should keep Platformer's blocks and words when the person picks their own status colours`() throws {
        let theme = ThemeRegistry.shared.resolveTheme(
            for: "platformer",
            systemColorScheme: .light,
            statusColors: StatusColorPolicy(overrides: StatusColorOverrides(healthy: RGBColorValue(red: 0, green: 0, blue: 1)), highContrastEnabled: false)
        )
        #expect(theme.progressStyle == .blocks(10))
        #expect(theme.statusWord(for: .depleted) == "GAME OVER")
        #expect(theme.tagline == PlatformerTheme().tagline)
    }

    @Test(arguments: ["light", "dark", "system", "cli", "christmas", "pop"])
    func `should keep every other theme's bar and plain status words`(id: String) throws {
        let theme = try #require(ThemeRegistry.shared.theme(for: id))
        #expect(theme.progressStyle == .bar)
        #expect(theme.displayFontScale == 1)
        #expect(theme.customFontName == nil)
        #expect(theme.statusWord(for: .critical) == "LOW")
        #expect(theme.statusWord(for: .depleted) == "EMPTY")
    }

    @Test func `should give each theme its own line under ClaudeBar's name`() throws {
        #expect(try #require(ThemeRegistry.shared.theme(for: "light")).tagline == nil)
        #expect(try #require(ThemeRegistry.shared.theme(for: "cli")).tagline == "> usage monitor")
        #expect(try #require(ThemeRegistry.shared.theme(for: "christmas")).tagline == "Happy Holidays!")
        #expect(try #require(ThemeRegistry.shared.theme(for: "pop")).tagline == "Your quotas, the cute way")
        #expect(PlatformerTheme().tagline == "Your quotas, one level at a time")
    }
}

/// A quota bar drawn as blocks: one block per tenth, rounded to the
/// nearest, and never empty while anything is left.
@Suite
struct ProgressBlocksTests {
    @Test func `should fill blocks to the nearest tenth`() {
        #expect(ProgressBlocks.filled(percent: 62, of: 10) == 6)
        #expect(ProgressBlocks.filled(percent: 66, of: 10) == 7)
        #expect(ProgressBlocks.filled(percent: 100, of: 10) == 10)
    }

    @Test func `should keep one block lit while a quota has anything left`() {
        #expect(ProgressBlocks.filled(percent: 2, of: 10) == 1)
    }

    @Test func `should light no block when a quota is empty`() {
        #expect(ProgressBlocks.filled(percent: 0, of: 10) == 0)
        #expect(ProgressBlocks.filled(percent: -5, of: 10) == 0)
    }

    @Test func `should never light more blocks than the bar has`() {
        #expect(ProgressBlocks.filled(percent: 140, of: 10) == 10)
    }
}

/// What Platformer adds to the popover — a choice of text style, square
/// controls, a brick floor the buttons stand on, a score line with a ?
/// block, a blinking HURRY UP! — and that no other theme changes.
@MainActor
@Suite
struct PlatformerLevelTests {
    @Test func `should let the person choose Pixel or Classic text in Platformer`() {
        #expect(PlatformerTheme().textStyleName == "Pixel")
    }

    @Test func `should print every word in pixels with Pixel text`() {
        let theme = PlatformerTheme().styled(.themed)
        #expect(theme.customFontName == "PixelifySans")
    }

    @Test func `should drop every pixel face with Classic text but keep the level`() {
        let theme = PlatformerTheme().styled(.classic)
        #expect(theme.customFontName == nil)
        #expect(theme.displayFontName == nil)
        #expect(theme.progressStyle == .blocks(10))
        #expect(theme.statusWord(for: .critical) == "HURRY UP!")
    }

    @Test func `should print square badges and rivet each card's corners`() {
        let theme = PlatformerTheme()
        #expect(theme.badgeCornerRadius == 0)
        #expect(theme.cardRivetSize == 4)
    }

    @Test func `should keep Classic text when the person also picks their own status colours`() {
        let theme = ThemeRegistry.shared.resolveTheme(
            for: "platformer",
            systemColorScheme: .light,
            statusColors: StatusColorPolicy(overrides: StatusColorOverrides(healthy: RGBColorValue(red: 0, green: 0, blue: 1)), highContrastEnabled: false),
            textStyle: .classic
        )
        #expect(theme.customFontName == nil)
        #expect(theme.statusWord(for: .depleted) == "GAME OVER")
    }

    @Test func `should square off Platformer's buttons and stand them on the brick floor`() {
        let theme = PlatformerTheme()
        #expect(theme.controlCornerRadius == 3)
        #expect(theme.groundHeight == 36)
    }

    @Test func `should head Platformer's popover with a score line and a ? block`() {
        #expect(PlatformerTheme().headerStyle == .scoreLine)
    }

    @Test func `should blink HURRY UP and nothing else`() {
        let theme = PlatformerTheme()
        #expect(theme.blinks(.critical))
        #expect(!theme.blinks(.healthy))
        #expect(!theme.blinks(.warning))
        #expect(!theme.blinks(.depleted))
    }

    @Test func `should write on Platformer's selected tab in ink`() {
        #expect(PlatformerTheme().textOnAccent == PlatformerTheme.ink)
    }

    @Test func `should write on CLI's selected tab in its own text colour`() throws {
        let cli = try #require(ThemeRegistry.shared.theme(for: "cli"))
        #expect(cli.textOnAccent == cli.textPrimary)
    }

    @Test(arguments: ["light", "dark", "system", "cli", "christmas", "pop"])
    func `should keep every other theme's round controls, header and steady badges`(id: String) throws {
        let theme = try #require(ThemeRegistry.shared.theme(for: id))
        #expect(theme.textStyleName == nil)
        #expect(theme.controlCornerRadius == nil)
        #expect(theme.groundHeight == 0)
        #expect(theme.headerStyle == .standard)
        #expect(!theme.blinks(.critical))
        #expect(theme.badgeCornerRadius == nil)
        #expect(theme.cardRivetSize == nil)
        // Another style changes nothing on a theme that offers none.
        #expect(theme.styled(.classic).customFontName == theme.customFontName)
    }
}

/// The score line across the top of Platformer's popover, read from the
/// selected provider like the rest of the popover: who, how it's doing,
/// how much is left as coins, which tab, and minutes until it resets.
@Suite
struct ScoreLineTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func `should name the provider and say how it is doing`() {
        let line = ScoreLine(providerName: "Claude", status: "HEALTHY", quotas: [], tab: 1, now: now)
        #expect(line.player == "CLAUDE")
        #expect(line.status == "HEALTHY")
    }

    @Test func `should count what is left of the first quota as coins`() {
        let quotas = [UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "claude"),
                      UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude")]
        let line = ScoreLine(providerName: "Claude", status: "HEALTHY", quotas: quotas, tab: 1, now: now)
        #expect(line.coins == "62")
    }

    @Test func `should count a balance's whole dollars as coins`() {
        let quotas = [UsageQuota(percentRemaining: 97, quotaType: .modelSpecific("Credits"), providerId: "openrouter", dollarRemaining: Decimal(string: "24.19"))]
        let line = ScoreLine(providerName: "OpenRouter", status: "HEALTHY", quotas: quotas, tab: 3, now: now)
        #expect(line.coins == "24")
    }

    @Test func `should number the world after the selected tab`() {
        let line = ScoreLine(providerName: "Codex", status: "HEALTHY", quotas: [], tab: 2, now: now)
        #expect(line.world == "1-2")
    }

    @Test func `should count down the minutes until the first quota resets`() {
        let quotas = [UsageQuota(percentRemaining: 62, quotaType: .session, providerId: "claude", resetsAt: now.addingTimeInterval(4 * 3600 + 48 * 60))]
        let line = ScoreLine(providerName: "Claude", status: "HEALTHY", quotas: quotas, tab: 1, now: now)
        #expect(line.time == "288")
    }

    @Test func `should cap a long countdown at 999 minutes`() {
        let quotas = [UsageQuota(percentRemaining: 62, quotaType: .weekly, providerId: "claude", resetsAt: now.addingTimeInterval(3 * 86400))]
        let line = ScoreLine(providerName: "Claude", status: "HEALTHY", quotas: quotas, tab: 1, now: now)
        #expect(line.time == "999")
    }

    @Test func `should show dashes when nothing is known yet`() {
        let line = ScoreLine(providerName: "Claude", status: "SYNCING", quotas: [], tab: 1, now: now)
        #expect(line.coins == "--")
        #expect(line.time == "---")
    }
}
