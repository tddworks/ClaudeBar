import Testing
import Foundation
import SwiftUI
import Domain
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
    func `CLI theme shows the outline terminal when no session is running`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: CLITheme(), status: .healthy, besideSessionGlyph: false
        )
        #expect(symbol == "terminal")
    }

    @Test
    func `the session glyph stands in for the CLI outline terminal`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: CLITheme(), status: .healthy, besideSessionGlyph: true
        )
        #expect(symbol == nil)
    }

    @Test
    func `a theme icon unrelated to the session glyph is kept beside it`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: ChristmasTheme(), status: .healthy, besideSessionGlyph: true
        )
        #expect(symbol == "snowflake")
    }

    @Test
    func `a theme without its own icon keeps the status shape beside the glyph`() {
        let symbol = StatusItemLabelDriver.statusIconSymbol(
            theme: DarkTheme(), status: .critical, besideSessionGlyph: true
        )
        #expect(symbol == "exclamationmark.triangle.fill")
    }

    // MARK: - Session glyph colour

    @Test
    func `the CLI terminal fills in with the quota status colour while Claude works`() {
        let theme = CLITheme()
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .active, theme: theme, status: .critical, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == theme.menuBarStatusColor(for: .critical, darkMenuBar: true))
    }

    @Test
    func `the CLI terminal keeps the quota status colour while subagents work`() {
        let theme = CLITheme()
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .subagentsWorking, theme: theme, status: .warning, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == theme.menuBarStatusColor(for: .warning, darkMenuBar: true))
    }

    @Test
    func `the glyph in front of usage text keeps the session colour in the CLI theme`() {
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .subagentsWorking, theme: CLITheme(), status: .critical, showsUsageText: true, darkMenuBar: true
        )
        #expect(color == ClaudeSession.Phase.subagentsWorking.color)
    }

    @Test
    func `the glyph beside an unrelated theme icon keeps the session colour`() {
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .active, theme: ChristmasTheme(), status: .critical, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == ClaudeSession.Phase.active.color)
    }

    @Test
    func `the glyph beside a status shape keeps the session colour`() {
        let color = StatusItemLabelDriver.sessionGlyphColor(
            phase: .active, theme: DarkTheme(), status: .critical, showsUsageText: false, darkMenuBar: true
        )
        #expect(color == ClaudeSession.Phase.active.color)
    }
}
