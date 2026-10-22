import Foundation
import Testing
@testable import Domain

/// The body a webhook carries: one line for Slack, one generic JSON object for a
/// script — decoded rather than byte-compared.
@MainActor
@Suite
struct WebhookBodyTests {
    /// A reading of *Claude · work*'s Weekly window.
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

    /// A body for one rule and the default reading.
    private func body(_ condition: Rule.Condition, channel: WebhookChannel = .slack, reading: RuleReading? = nil) -> WebhookBody {
        WebhookBody(
            rule: Rule(id: "r1", condition: condition, action: .webhook(channel: channel)),
            reading: reading ?? self.reading()
        )
    }

    /// The body's bytes as a JSON object, so a test reads fields, not bytes.
    private func decode(_ body: WebhookBody) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try body.encoded()) as? [String: Any])
    }

    // MARK: - Slack

    /// A *below* Slack body is the one line the person reads.
    @Test func `should say a below in the person's words`() throws {
        let json = try decode(body(.below(percent: 35)))

        #expect(json["text"] as? String == "Claude · work is below 35% — 34% left")
    }

    /// A *critical* Slack body names the window and what is left.
    @Test func `should say a critical in the person's words`() throws {
        let json = try decode(body(.critical))

        #expect(json["text"] as? String == "Claude · work is critical — Weekly at 34% left")
    }

    /// A *depleted* Slack body names the window alone.
    @Test func `should say a depleted in the person's words`() throws {
        let json = try decode(body(.depleted, reading: reading(percentLeft: nil, status: .depleted)))

        #expect(json["text"] as? String == "Claude · work is depleted — Weekly")
    }

    // MARK: - Generic JSON

    /// A generic body states every field a consumer reads.
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

    /// A field with no value is a null, never absent.
    @Test func `should state a null rather than leave a field out`() throws {
        let json = try decode(body(.depleted, channel: .json, reading: reading(percentLeft: nil, resetsAt: nil, status: .depleted)))

        #expect(json["condition"] as? String == "depleted")
        #expect(json["percent"] is NSNull)
        #expect(json["percentLeft"] is NSNull)
        #expect(json["resetsAt"] is NSNull)
        #expect(json["status"] as? String == "depleted")
    }

    /// A *critical* carries no percent, only its condition.
    @Test func `should carry no percent for a critical`() throws {
        let json = try decode(body(.critical, channel: .json, reading: reading(status: .critical)))

        #expect(json["condition"] as? String == "critical")
        #expect(json["percent"] is NSNull)
        #expect(json["status"] as? String == "critical")
    }

    /// The body and the channel name the channel the rule chose.
    @Test func `should name the channel it sends through`() {
        #expect(body(.critical).channel == .slack)
        #expect(body(.critical, channel: .json).channel == .json)
        #expect(WebhookChannel.slack.displayName == "Slack")
        #expect(WebhookChannel.json.displayName == "JSON")
    }
}