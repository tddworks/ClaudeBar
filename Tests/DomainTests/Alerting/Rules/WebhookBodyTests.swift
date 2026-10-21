import Foundation
import Testing
@testable import Domain

/// The body a webhook carries: one line for Slack, one generic JSON object for a
/// script — decoded rather than byte-compared.
@MainActor
@Suite
struct WebhookBodyTests {
    private func reading(
        percentLeft: Int? = 34,
        resetsAt: Date? = nil,
        status: QuotaStatus = .warning
    ) -> RuleReading {
        RuleReading(
            login: "Claude · work",
            loginId: "claude.work",
            providerId: "claude",
            window: "Weekly",
            percentLeft: percentLeft,
            resetsAt: resetsAt,
            status: status
        )
    }

    private func body(_ condition: Rule.Condition, channel: WebhookChannel = .slack, reading: RuleReading? = nil) -> WebhookBody {
        WebhookBody(
            rule: Rule(id: "r1", condition: condition, action: .webhook(channel: channel)),
            reading: reading ?? self.reading()
        )
    }

    private func decode(_ body: WebhookBody) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try body.encoded()) as? [String: Any])
    }

    // MARK: - Slack

    @Test func `should say a below in the person's words`() throws {
        let json = try decode(body(.below(percent: 35)))

        #expect(json["text"] as? String == "Claude · work is below 35% — 34% left")
    }

    @Test func `should say a critical in the person's words`() throws {
        let json = try decode(body(.critical))

        #expect(json["text"] as? String == "Claude · work is critical — Weekly at 34% left")
    }

    @Test func `should say a depleted in the person's words`() throws {
        let json = try decode(body(.depleted, reading: reading(percentLeft: nil, status: .depleted)))

        #expect(json["text"] as? String == "Claude · work is depleted — Weekly")
    }

    // MARK: - Generic JSON

    @Test func `should state every field of a generic body`() throws {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let json = try decode(body(.below(percent: 35), channel: .json, reading: reading(resetsAt: when)))

        #expect(json["ruleId"] as? String == "r1")
        #expect(json["condition"] as? String == "below")
        #expect(json["percent"] as? Int == 35)
        #expect(json["provider"] as? String == "claude")
        #expect(json["login"] as? String == "Claude · work")
        #expect(json["window"] as? String == "Weekly")
        #expect(json["percentLeft"] as? Int == 34)
        #expect(json["status"] as? String == "warning")
        #expect(json["resetsAt"] as? String == ISO8601DateFormatter().string(from: when))
    }

    @Test func `should state a null rather than leave a field out`() throws {
        let json = try decode(body(.depleted, channel: .json, reading: reading(percentLeft: nil, resetsAt: nil, status: .depleted)))

        #expect(json["condition"] as? String == "depleted")
        #expect(json["percent"] is NSNull)
        #expect(json["percentLeft"] is NSNull)
        #expect(json["resetsAt"] is NSNull)
        #expect(json["status"] as? String == "depleted")
    }

    @Test func `should carry no percent for a critical`() throws {
        let json = try decode(body(.critical, channel: .json, reading: reading(status: .critical)))

        #expect(json["condition"] as? String == "critical")
        #expect(json["percent"] is NSNull)
        #expect(json["status"] as? String == "critical")
    }

    @Test func `should name the channel it sends through`() {
        #expect(body(.critical).channel == .slack)
        #expect(body(.critical, channel: .json).channel == .json)
        #expect(WebhookChannel.slack.displayName == "Slack")
        #expect(WebhookChannel.json.displayName == "JSON")
    }
}