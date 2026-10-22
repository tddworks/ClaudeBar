import Testing
import Foundation
@testable import ClaudeBar

@Suite
struct URLSchemeActionTests {

    @Test(arguments: [
        ("claudebar://open", URLSchemeAction.open),
        ("claudebar://refresh", .refresh),
        ("claudebar://settings", .settings),
    ])
    func `should open, refresh or show settings for each documented link`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test(arguments: [
        ("claudebar:///open", URLSchemeAction.open),
        ("claudebar:///refresh", .refresh),
        ("claudebar:///settings", .settings),
    ])
    func `should treat the three-slash spelling of a link as the same action`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test
    func `should accept a link whatever its letter case`() {
        let url = URL(string: "CLAUDEBAR://Open")!
        #expect(URLSchemeAction(url: url) == .open)
    }

    @Test(arguments: [
        "claudebar://foo",
        "claudebar://",
        "claudebar:///",
        "claudebar://refresh/other?unexpected=1",
        "claudebar://open?x=1",
        "claudebar://open#top",
        "claudebar://open/",
        "claudebar://open/extra",
        "claudebar:///open/extra",
        "claudebar:///settings/",
        "claudebar:///settings?x=1",
        "claudebar://guest@refresh",
        "claudebar://refresh:443",
        "claudebar://user:pass@settings",
        "https://open",
    ])
    func `should ignore any link that is not exactly a documented one`(string: String) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == nil)
    }

    // MARK: - enable: one click back on after auto-pause

    @Test(arguments: [
        ("claudebar://enable?provider=claude", "claude"),
        ("claudebar:///enable?provider=codex", "codex"),
        // Real ids aren't all builtin-shaped: extensions are `ext-<manifest id>`,
        // custom ones come from an imported definition. The parser refuses only
        // the unsafe; the handler resolves the name against the products.
        ("claudebar://enable?provider=ext-my-tool.v2", "ext-my-tool.v2"),
        ("claudebar://enable?provider=ext-a-very-long-extension-identifier-1234567890",
         "ext-a-very-long-extension-identifier-1234567890"),
    ])
    func `should turn the named provider back on from an enable link`(string: String, provider: String) {
        #expect(URLSchemeAction(url: URL(string: string)!) == .enable(provider: provider))
    }

    @Test(arguments: [
        "claudebar://enable",
        "claudebar://enable?provider=",
        "claudebar://enable?provider=claude&x=1",
        "claudebar://enable?provider=claude&provider=codex",
        "claudebar://enable?provider=claude%0A",
        "claudebar://enable?provider=claude&account=work",
        "claudebar://enable/extra?provider=claude",
        "claudebar://enable?provider=claude#top",
    ])
    func `should ignore an enable link that isn't exactly one provider`(string: String) {
        #expect(URLSchemeAction(url: URL(string: string)!) == nil)
    }

    // MARK: - use: which login new terminal sessions start with

    @Test(arguments: [
        ("claudebar://use?provider=claude&account=work", "claude", "work"),
        ("claudebar:///use?provider=codex&account=default", "codex", "default"),
        ("claudebar://use?account=Work%20%E2%80%94%20Acme&provider=claude", "claude", "Work — Acme"),
    ])
    func `should pick the named provider's login for new terminal sessions from a use link`(string: String, provider: String, account: String) {
        #expect(URLSchemeAction(url: URL(string: string)!) == .use(provider: provider, account: account))
    }

    @Test(arguments: [
        "claudebar://use",
        "claudebar://use?provider=claude",
        "claudebar://use?account=work",
        "claudebar://use?provider=claude&account=",
        "claudebar://use?provider=claude&account=work&x=1",
        "claudebar://use?provider=claude&provider=codex&account=work",
        "claudebar://use?provider=../claude&account=work",
        "claudebar://use/extra?provider=claude&account=work",
        "claudebar://use?provider=claude&account=work#top",
        "claudebar://guest@use?provider=claude&account=work",
    ])
    func `should ignore a use link that isn't exactly one provider and one login`(string: String) {
        #expect(URLSchemeAction(url: URL(string: string)!) == nil)
    }
}
