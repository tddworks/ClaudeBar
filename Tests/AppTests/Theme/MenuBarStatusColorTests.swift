import Domain
import SwiftUI
import Testing
@testable import ClaudeBar

/// The menu bar is the system's light or dark strip, so status text there
/// must read on both. Pop's candy pastels vanish on a light menu bar, so it
/// uses deeper versions there; a colour the person chose always wins.
@MainActor
@Suite
struct MenuBarStatusColorTests {
    @Test func `on a dark menu bar Pop keeps its candy colours`() {
        let pop = PopTheme()
        for status in [QuotaStatus.healthy, .warning, .critical, .depleted] {
            #expect(pop.menuBarStatusColor(for: status, darkMenuBar: true) == pop.statusColor(for: status))
        }
    }

    @Test func `on a light menu bar Pop uses deep colours that read`() {
        let pop = PopTheme()
        #expect(pop.menuBarStatusColor(for: .healthy, darkMenuBar: false) == PopTheme.mintDeep)
        #expect(pop.menuBarStatusColor(for: .warning, darkMenuBar: false) == PopTheme.amber)
        #expect(pop.menuBarStatusColor(for: .critical, darkMenuBar: false) == PopTheme.coralDeep)
        #expect(pop.menuBarStatusColor(for: .depleted, darkMenuBar: false) == PopTheme.coralDeep)
    }

    @Test(arguments: ["light", "dark", "cli", "christmas"])
    func `other themes use their status colours in the menu bar`(id: String) throws {
        let theme = try #require(ThemeRegistry.shared.theme(for: id))
        for dark in [true, false] {
            #expect(theme.menuBarStatusColor(for: .healthy, darkMenuBar: dark) == theme.statusColor(for: .healthy))
        }
    }

    @Test func `a status colour the person chose wins over Pop's menu bar colour`() {
        var overrides = StatusColorOverrides.none
        overrides[.healthy] = RGBColorValue(red: 0, green: 0, blue: 1)
        let theme = ThemeRegistry.shared.resolveTheme(for: "pop", systemColorScheme: .light,
                                                      statusColors: StatusColorPolicy(overrides: overrides, highContrastEnabled: false))
        #expect(theme.menuBarStatusColor(for: .healthy, darkMenuBar: false) == theme.statusColor(for: .healthy))
        #expect(theme.menuBarStatusColor(for: .warning, darkMenuBar: false) == PopTheme.amber)
    }
}

/// Pop's quota in the menu bar is a candy chip: status colour, ink outline
/// and text, a hard shadow — and it always fits the 22 pt menu bar.
@MainActor
@Suite
struct MenuBarChipTests {
    @Test func `a chip wraps its label and fits the menu bar`() {
        let text = StatusBarPercentageImageRenderer.image(text: "5h 82% · 3:07", color: PopTheme().textOnStatus)
        let chip = StatusBarChipRenderer.chip(text, fill: PopTheme().statusHealthy, ink: PopTheme().glassBorder, shadow: true)
        #expect(chip.size.width > text.size.width + 10)
        #expect(chip.size.height <= 22)
    }
}
