import Foundation
import Quotas

/// The payload a webhook carries. One case per channel; a new channel is a case
/// here and nothing else moves.
public enum WebhookChannel: String, Sendable, Equatable, Codable, CaseIterable {
    /// A Slack incoming webhook: `{"text": …}`.
    case slack
    /// A generic JSON body, for a script or a service of the person's own.
    case json

    /// The channel as the pane names it.
    public var displayName: String {
        switch self {
        case .slack: "Slack"
        case .json: "JSON"
        }
    }
}

/// One rule's moment, as a body for its channel. Pure: the same rule and the
/// same reading always encode the same bytes, so a test decodes rather than
/// compares.
public struct WebhookBody: Sendable, Equatable {
    public let rule: Rule
    public let reading: RuleReading

    /// A body pairing the rule with the reading that met it.
    public init(rule: Rule, reading: RuleReading) {
        self.rule = rule
        self.reading = reading
    }

    /// The channel the rule chose.
    public var channel: WebhookChannel {
        switch rule.action {
        case .webhook(let channel): channel
        }
    }

    /// The one line a person reads in Slack.
    public var message: String {
        switch rule.condition {
        case .below(let percent):
            "\(reading.login) is below \(percent)% — \(reading.percentLeft ?? 0)% left"
        case .critical:
            "\(reading.login) is critical — \(reading.window) at \(reading.percentLeft ?? 0)% left"
        case .depleted:
            "\(reading.login) is depleted — \(reading.window)"
        }
    }

    /// The bytes to POST for the rule's channel: Slack's one line, or the generic
    /// JSON.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        switch channel {
        case .slack:
            return try encoder.encode(SlackPayload(text: message))
        case .json:
            return try encoder.encode(jsonPayload)
        }
    }

    /// The rule's condition, as a machine reads it: `below` carries its percent.
    private var conditionName: String {
        switch rule.condition {
        case .below: "below"
        case .critical: "critical"
        case .depleted: "depleted"
        }
    }

    /// The percent a `below` carries; nil for `critical` and `depleted`.
    private var conditionPercent: Int? {
        switch rule.condition {
        case .below(let percent): percent
        case .critical, .depleted: nil
        }
    }

    /// The generic body's fields, read from the rule and the reading.
    private var jsonPayload: JSONPayload {
        JSONPayload(
            ruleId: rule.id,
            condition: conditionName,
            percent: conditionPercent,
            provider: reading.providerId,
            login: reading.login,
            window: reading.window,
            percentLeft: reading.percentLeft,
            resetsAt: reading.resetsAt,
            status: reading.status.name
        )
    }
}

/// A Slack incoming webhook's body.
private struct SlackPayload: Encodable {
    let text: String
}

/// A generic JSON body. Every field is stated on every send — a null where
/// there is no value — so a consumer never has to guess whether a field is
/// absent or empty.
private struct JSONPayload: Encodable {
    let ruleId: String
    let condition: String
    let percent: Int?
    let provider: String
    let login: String
    let window: String
    let percentLeft: Int?
    let resetsAt: Date?
    let status: String

    enum CodingKeys: String, CodingKey {
        case ruleId, condition, percent, provider, login, window, percentLeft, resetsAt, status
    }

    /// Writes every key, so no field is ever absent.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ruleId, forKey: .ruleId)
        try container.encode(condition, forKey: .condition)
        try container.encode(percent, forKey: .percent)
        try container.encode(provider, forKey: .provider)
        try container.encode(login, forKey: .login)
        try container.encode(window, forKey: .window)
        try container.encode(percentLeft, forKey: .percentLeft)
        try container.encode(resetsAt, forKey: .resetsAt)
        try container.encode(status, forKey: .status)
    }
}

extension QuotaStatus {
    /// The status as a payload names it.
    var name: String {
        switch self {
        case .healthy: "healthy"
        case .warning: "warning"
        case .critical: "critical"
        case .depleted: "depleted"
        }
    }
}