import Foundation
import Testing
@testable import Domain

/// A webhook's URL: https, or http only to this Mac or the person's network.
@Suite
struct WebhookAddressTests {
    private func refusal(_ text: String) -> WebhookAddress.Refusal? {
        do { _ = try WebhookAddress(text); return nil } catch { return error }
    }

    @Test func `should take an https URL`() throws {
        let address = try WebhookAddress("https://hooks.slack.com/services/T000/B000/XXXX")

        #expect(address.host == "hooks.slack.com")
        #expect(address.url.absoluteString == "https://hooks.slack.com/services/T000/B000/XXXX")
    }

    @Test func `should take a pasted URL with stray spaces`() throws {
        #expect(try WebhookAddress("  https://ops.example.com/hook\n").host == "ops.example.com")
    }

    @Test(arguments: [
        "http://localhost:8080/claudebar", "http://127.0.0.1/hook", "http://[::1]:9000/hook",
        "http://10.0.0.4/hook", "http://172.16.0.1/hook", "http://172.31.255.1/hook",
        "http://192.168.1.20:8080/claudebar", "http://mac-mini.local/hook",
    ])
    func `should take http to this Mac or the person's network`(url: String) {
        #expect(refusal(url) == nil)
    }

    @Test(arguments: [
        "http://ops.example.com/hook", "http://8.8.8.8/hook", "http://172.32.0.1/hook",
        "http://192.169.1.1/hook", "http://localhost.example.com/hook",
    ])
    func `should refuse http to a host on the internet`(url: String) {
        #expect(refusal(url) == .notHTTPS)
    }

    @Test(arguments: ["", "hooks.slack.com/services/T000", "ftp://example.com/x", "https://", "not a url"])
    func `should refuse what is not a full web URL`(text: String) {
        #expect(refusal(text) == .notAURL)
    }
}
