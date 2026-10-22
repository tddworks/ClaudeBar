import Foundation

/// What a webhook POSTs: an alert, or a test, shaped for its channel. Slack
/// gets one line, the words of the Mac's notification; JSON gets every key on
/// every send, `null` where there is no value. A test says it is a test and is
/// never shaped like an alert.
public struct WebhookBody: Sendable, Equatable {
    /// What is being sent.
    public enum Message: Sendable, Equatable {
        case alert(Alert)
        /// *Send a test*: no login, no quota judged.
        case test
    }

    public let message: Message
    public let channel: WebhookChannel
    public let sentAt: Date

    public init(_ message: Message, channel: WebhookChannel, sentAt: Date) {
        self.message = message
        self.channel = channel
        self.sentAt = sentAt
    }

    /// The bytes to POST.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Both payloads are plain strings, numbers and nulls: encoding can't fail.
        return switch channel {
        case .slack: (try? encoder.encode(["text": line])) ?? Data()
        case .json: (try? encoder.encode(JSONPayload(message, sentAt: sentAt))) ?? Data()
        }
    }

    /// The one line a person reads in Slack.
    var line: String {
        switch message {
        case .alert(.quota(let alert)): "\(alert.login) is below \(alert.below)% — \(alert.left)% left"
        case .alert(.status(let alert)): "\(alert.login) is \(alert.now.payloadName) — was \(alert.was.payloadName)"
        case .test: "ClaudeBar test — this webhook works. No quota was judged."
        }
    }
}

/// The JSON body. Every key is written on every send, so a consumer never has
/// to tell an absent field from an empty one.
private struct JSONPayload: Encodable {
    let type: String
    let provider: String?
    let login: String?
    let below: Int?
    let left: Int?
    let status: String?
    let was: String?
    let sentAt: Date

    init(_ message: WebhookBody.Message, sentAt: Date) {
        self.sentAt = sentAt
        switch message {
        case .alert(.quota(let alert)):
            type = "quota"; provider = alert.providerId; login = alert.login
            below = alert.below; left = alert.left; status = nil; was = nil
        case .alert(.status(let alert)):
            type = "status"; provider = alert.providerId; login = alert.login
            below = nil; left = nil; status = alert.now.payloadName; was = alert.was.payloadName
        case .test:
            type = "test"; provider = nil; login = nil; below = nil; left = nil; status = nil; was = nil
        }
    }

    enum CodingKeys: String, CodingKey { case type, provider, login, below, left, status, was, sentAt }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(provider, forKey: .provider)
        try container.encode(login, forKey: .login)
        try container.encode(below, forKey: .below)
        try container.encode(left, forKey: .left)
        try container.encode(status, forKey: .status)
        try container.encode(was, forKey: .was)
        try container.encode(sentAt, forKey: .sentAt)
    }
}

extension QuotaStatus {
    /// The status as a payload names it.
    var payloadName: String {
        switch self {
        case .healthy: "healthy"
        case .warning: "warning"
        case .critical: "critical"
        case .depleted: "depleted"
        }
    }
}
