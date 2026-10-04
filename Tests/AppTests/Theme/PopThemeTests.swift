import SwiftUI
import Testing
@testable import ClaudeBar

/// Pop: cream paper, thick ink outlines, hard offset shadows, candy status
/// colours with ink text on them, and big numbers in Lilita One. Every
/// other theme keeps its thin outline, no hard shadow and white badge text.
@MainActor
@Suite
struct PopThemeTests {
    @Test func `Pop is a built-in theme, picked as a light one`() {
        #expect(ThemeRegistry.shared.theme(for: "pop")?.displayName == "Pop")
        #expect(ThemeMode(rawValue: "pop") == .pop)
    }

    @Test func `Pop outlines in ink, with a hard shadow`() {
        let pop = PopTheme()
        #expect(pop.cardBorderWidth == 2.5)
        #expect(pop.glassBorder == PopTheme.ink)
        #expect(pop.cardShadow == ThemeShadow(color: PopTheme.ink, radius: 0, x: 4, y: 4))
        // Outlined: Settings draws paper, inked selections and switches for it.
        #expect(pop.isOutlined)
    }

    @Test func `badges on Pop's candy colours are written in ink`() {
        #expect(PopTheme().textOnStatus == PopTheme.ink)
    }

    @Test func `Pop's big numbers are in its display font, which ships with the app`() {
        #expect(PopTheme().displayFontName == "LilitaOne")
    }

    @Test(arguments: ["light", "dark", "system", "cli", "christmas"])
    func `every other theme looks as it did`(id: String) throws {
        let theme = try #require(ThemeRegistry.shared.theme(for: id))
        #expect(theme.cardBorderWidth == 1)
        #expect(theme.cardShadow == nil)
        #expect(theme.displayFontName == nil)
        #expect(theme.textOnStatus == .white)
        #expect(!theme.isOutlined)
    }
}
