import Testing
@testable import ClaudeBar

/// The few characters beside a provider's icon in the menu bar that say which
/// of its logins a number belongs to. Full names stay in the tooltip; a short
/// name never grows back into a full email to stay unique.
@Suite
struct MenuBarAccountNameTests {
    @Test
    func `an email shows its name before the at sign`() {
        let names = MenuBarAccountName.names(["codex": "me@example.com", "codex.a": "work@acme.com"])

        #expect(names == ["codex": "me", "codex.a": "work"])
    }

    @Test
    func `a long email name is cut to eight characters`() {
        let names = MenuBarAccountName.names(["codex.a": "henry.personal@example.com"])

        #expect(names["codex.a"] == "henry.p…")
    }

    @Test
    func `a given name keeps up to twelve characters`() {
        let names = MenuBarAccountName.names(["claude": "Side Project", "claude.w": "Work — Acme Corp"])

        #expect(names["claude"] == "Side Project")
        #expect(names["claude.w"] == "Work — Acme…")
    }

    @Test
    func `names that shorten alike are numbered, never widened`() {
        let names = MenuBarAccountName.names([
            "codex.a": "same-long-one@example.com",
            "codex.b": "same-long-two@example.com",
        ])

        #expect(names["codex.a"] == "same-l·1")
        #expect(names["codex.b"] == "same-l·2")
        #expect(names.values.allSatisfy { $0.count <= 8 })
    }

    @Test
    func `the same name on two logins is numbered`() {
        let names = MenuBarAccountName.names(["claude": "Work", "claude.w": "Work"])

        #expect(names["claude"] == "Work·1")
        #expect(names["claude.w"] == "Work·2")
    }
}
