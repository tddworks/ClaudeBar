import Testing
import Foundation
import SwiftUI
import Kit
@testable import ClaudeBar

/// When no usage text is shown, the menu bar draws the theme's status icon,
/// and while a Claude Code session is working it draws a filled terminal glyph
/// in the phase colour. The CLI theme's icon is the outline of that glyph, so
/// the two collapse into one terminal that fills in while Claude works —
/// before this, the CLI icon was the filled terminal too and the bar showed
/// the same green terminal twice. The one terminal keeps the quota status
/// colour, so its shape says whether Claude is working and its colour still
/// says how the quota is doing.
@Suite @MainActor
struct StatusItemStatusIconTests {

    @Test
    func `should show the CLI theme's outline terminal when no session is running`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: CLITheme(), status: .healthy, besideSessionGlyph: false
        )
        #expect(symbol == "terminal")
    }

    @Test
    func `should show one terminal, not two, while a session runs in the CLI theme`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: CLITheme(), status: .healthy, besideSessionGlyph: true
        )
        #expect(symbol == nil)
    }

    @Test
    func `should keep a theme's own icon beside the session glyph`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: ChristmasTheme(), status: .healthy, besideSessionGlyph: true
        )
        #expect(symbol == "snowflake")
    }

    @Test
    func `should keep the status shape beside the session glyph when the theme has no icon of its own`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: DarkTheme(), status: .critical, besideSessionGlyph: true
        )
        #expect(symbol == "exclamationmark.triangle.fill")
    }

    // MARK: - Session glyph colour

    @Test
    func `should fill the CLI terminal in the quota's status colour while Claude works`() {
        let theme = CLITheme()
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .active, theme: theme, status: .critical, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == theme.menuBarStatusColor(for: .critical, darkMenuBar: true))
    }

    @Test
    func `should keep the CLI terminal in the quota's status colour while subagents work`() {
        let theme = CLITheme()
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .subagentsWorking, theme: theme, status: .warning, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == theme.menuBarStatusColor(for: .warning, darkMenuBar: true))
    }

    @Test
    func `should show the session colour on the glyph in front of usage text in the CLI theme`() {
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .subagentsWorking, theme: CLITheme(), status: .critical, showsUsageText: true, darkMenuBar: true
        )
        #expect(color == Session.Phase.subagentsWorking.color)
    }

    @Test
    func `should show the session colour on the glyph beside a theme's own icon`() {
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .active, theme: ChristmasTheme(), status: .critical, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == Session.Phase.active.color)
    }

    @Test
    func `should show the session colour on the glyph beside a status shape`() {
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .active, theme: DarkTheme(), status: .critical, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == Session.Phase.active.color)
    }
}
