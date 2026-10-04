import Foundation
import Mockable
import Testing
@testable import DataSources

/// `browserCookies` — *COOKIE SOURCE*: the first store holding a named cookie.
@Suite
struct BrowserCookieTests {
    private func reader(_ format: BrowserCookieCredential.Format, stores: [[BrowserCookie]]) -> BrowserCookieReader {
        let cookies = MockBrowserCookieReading()
        given(cookies).stores(domains: .value(["acme.test"]), names: .value(["session", "csrf"])).willReturn(stores)
        return BrowserCookieReader(query: BrowserCookieCredential(domains: ["acme.test"], names: ["session", "csrf"], format: format),
                                   cookies: cookies)
    }

    @Test
    func `value format answers the first named cookie's value`() throws {
        let found = try reader(.value, stores: [[BrowserCookie(name: "session", value: "s-1"), BrowserCookie(name: "csrf", value: "c-1")]]).find()
        #expect(found?.credential.token == "s-1")
    }

    @Test
    func `header format answers every named cookie as a Cookie header`() throws {
        let found = try reader(.header, stores: [[BrowserCookie(name: "session", value: "s-1"), BrowserCookie(name: "csrf", value: "c-1")]]).find()
        #expect(found?.credential.token == "session=s-1; csrf=c-1")
    }

    @Test
    func `a store with only empty cookies is passed over for the next`() throws {
        let found = try reader(.value, stores: [[BrowserCookie(name: "session", value: "")], [BrowserCookie(name: "session", value: "s-2")]]).find()
        #expect(found?.credential.token == "s-2")
    }

    @Test
    func `no browser signed in finds no key`() throws {
        #expect(try reader(.value, stores: []).find() == nil)
    }

    @Test
    func `the lookup order names the site, never a value`() throws {
        let lookup = try JSONDecoder().decode(CredentialLookup.self, from: Data(#"{"browserCookies":{"domains":["acme.test"],"names":["session"]}}"#.utf8))
        #expect(lookup.lookupOrder == ["Browser cookies for acme.test"])
        #expect(lookup == .browserCookies(BrowserCookieCredential(domains: ["acme.test"], names: ["session"])))
    }
}
