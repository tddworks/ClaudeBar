import Foundation

/// How a webhook's body is shaped. A new channel is a case here and in
/// `WebhookBody`, and nothing else moves.
public enum WebhookChannel: String, Sendable, Equatable, Codable, CaseIterable {
    /// A Slack incoming webhook: `{"text": …}`.
    case slack
    /// A JSON body, for a script or a service of the person's own.
    case json
}

/// Why a send didn't arrive. None carries the URL.
public enum WebhookFailure: Sendable, Equatable {
    /// The URL answered outside 2xx.
    case status(Int)
    /// No answer within the client's timeout.
    case timedOut
    /// The host couldn't be reached.
    case unreachable
    /// The URL redirected to another origin, which a URL carrying a token never follows.
    case redirectedAway
    /// The webhook's URL is no longer kept.
    case noURL
}

/// What one POST came to.
public enum WebhookPost: Sendable, Equatable {
    case sent
    case failed(WebhookFailure)
}

/// A webhook's last delivery — an alert's or a test's. Kept in memory: after
/// a relaunch nothing has been sent yet.
public enum WebhookDelivery: Sendable, Equatable {
    case neverSent
    case sending
    case sent(at: Date)
    case failed(WebhookFailure, at: Date)
}

/// One URL the person owns, with how and what it is sent. It has no percent of
/// its own: it sends the alerts `QuotaAlerts` and `StatusAlerts` decide, and
/// the week's recap when `RecapAlerts` says it is due
/// ([design](docs/features/alerting/webhooks/design.md)).
public struct Webhook: Sendable, Equatable, Identifiable {
    /// Which logins' alerts it sends.
    public enum Scope: Sendable, Equatable, Hashable {
        case everyLogin
        /// Every login of one product, by its id.
        case provider(String)
    }

    /// Which kinds of send it carries.
    public struct Sends: Sendable, Equatable {
        public var quotaAlerts: Bool
        public var statusAlerts: Bool
        /// The week that closed, each calendar week turn — a third kind of
        /// send is a field here and a case in `WebhookBody`, and nothing else
        /// moves ([recap alerts](docs/features/alerting/recap-alerts/design.md)).
        public var recap: Bool

        public init(quotaAlerts: Bool, statusAlerts: Bool, recap: Bool = false) {
            self.quotaAlerts = quotaAlerts
            self.statusAlerts = statusAlerts
            self.recap = recap
        }

        /// No kind at all: a webhook that would never send.
        public var isNothing: Bool { !quotaAlerts && !statusAlerts && !recap }
    }

    public let id: String
    /// What the list shows.
    public var name: String
    public var channel: WebhookChannel
    public var scope: Scope
    public var sends: Sends
    /// A webhook turned off keeps its place, its URL and its last delivery.
    public var isOn: Bool
    /// The URL's host, read from the kept URL; never saved.
    public internal(set) var host: String
    /// The last delivery; never saved.
    public internal(set) var delivery: WebhookDelivery

    public init(id: String, name: String, channel: WebhookChannel, scope: Scope, sends: Sends, isOn: Bool,
                host: String = "", delivery: WebhookDelivery = .neverSent) {
        self.id = id
        self.name = name
        self.channel = channel
        self.scope = scope
        self.sends = sends
        self.isOn = isOn
        self.host = host
        self.delivery = delivery
    }

    /// Whether it sends `alert`: it is on, sends that kind, and the alert's
    /// login is in its scope.
    public func wants(_ alert: Alert) -> Bool {
        guard isOn else { return false }
        let sendsKind = switch alert {
        case .quota: sends.quotaAlerts
        case .status: sends.statusAlerts
        }
        guard sendsKind else { return false }
        return switch scope {
        case .everyLogin: true
        case .provider(let id): alert.providerId == id
        }
    }

    /// Whether it sends the week's recap: it is on and sends recaps. Scope is
    /// never judged — the recap is one read across every provider, so no
    /// login and no provider is in or out of it.
    public func wants(_ recap: RecapAlert) -> Bool {
        isOn && sends.recap
    }
}
