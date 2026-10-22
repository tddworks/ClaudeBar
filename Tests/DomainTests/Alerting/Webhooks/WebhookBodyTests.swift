import Foundation
import Testing
@testable import Domain

/// How an alert, or a test, reads in Slack and as JSON.
@Suite
struct WebhookBodyTests {
    private let sentAt = Date(timeIntervalSince1970: 1_792_662_060) // 2026-10-22T09:41:00Z
    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Claude · work", providerId: "claude", was: .warning, now: .critical))

    private func slackText(_ message: WebhookBody.Message) throws -> String? {
        let data = WebhookBody(message, channel: .slack, sentAt: sentAt).encoded()
        return (try JSONSerialization.jsonObject(with: data) as? [String: String])?["text"]
    }

    private func json(_ message: WebhookBody.Message) throws -> [String: Any] {
        let data = WebhookBody(message, channel: .json, sentAt: sentAt).encoded()
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Slack

    @Test func `should say in Slack which login fell below which percent and what is left`() throws {
        #expect(try slackText(.alert(quota)) == "Claude · work is below 35% — 34% left")
    }

    @Test func `should say in Slack which status a login got worse to, and from`() throws {
        #expect(try slackText(.alert(status)) == "Claude · work is critical — was warning")
    }

    @Test func `should label a test as a test in Slack`() throws {
        #expect(try slackText(.test) == "ClaudeBar test — this webhook works. No quota was judged.")
    }

    // MARK: - JSON

    @Test func `should send a quota alert as JSON with its percent and what is left`() throws {
        let body = try json(.alert(quota))

        #expect(body["type"] as? String == "quota")
        #expect(body["provider"] as? String == "claude")
        #expect(body["login"] as? String == "Claude · work")
        #expect(body["below"] as? Int == 35)
        #expect(body["left"] as? Int == 34)
        #expect(body["status"] is NSNull)
        #expect(body["was"] is NSNull)
        #expect(body["sentAt"] as? String == "2026-10-22T09:41:00Z")
    }

    @Test func `should send a status alert as JSON with the status and what it was`() throws {
        let body = try json(.alert(status))

        #expect(body["type"] as? String == "status")
        #expect(body["status"] as? String == "critical")
        #expect(body["was"] as? String == "warning")
        #expect(body["below"] is NSNull)
        #expect(body["left"] is NSNull)
    }

    @Test func `should send a test as JSON naming no login`() throws {
        let body = try json(.test)

        #expect(body["type"] as? String == "test")
        #expect(body["provider"] is NSNull)
        #expect(body["login"] is NSNull)
        #expect(body["below"] is NSNull)
        #expect(body["status"] is NSNull)
    }

    @Test(arguments: [WebhookBody.Message.test, .alert(Alert.quota(QuotaAlert(login: "C", providerId: "c", below: 1, left: 0)))])
    func `should state every key on every JSON send`(message: WebhookBody.Message) throws {
        #expect(Set(try json(message).keys) == ["type", "provider", "login", "below", "left", "status", "was", "sentAt"])
    }
}
