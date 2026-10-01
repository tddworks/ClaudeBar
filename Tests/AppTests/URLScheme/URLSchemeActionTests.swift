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
    func `the documented URLs are actions`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test(arguments: [
        ("claudebar:///open", URLSchemeAction.open),
        ("claudebar:///refresh", .refresh),
        ("claudebar:///settings", .settings),
    ])
    func `the three-slash spelling is the same action`(string: String, expected: URLSchemeAction) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == expected)
    }

    @Test
    func `scheme and action are matched case-insensitively`() {
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
    func `anything that is not exactly a documented URL is nil`(string: String) {
        let url = URL(string: string)!
        #expect(URLSchemeAction(url: url) == nil)
    }
}
