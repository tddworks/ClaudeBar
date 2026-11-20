import Foundation
import Mockable
import Providers

/// *Alerting* for In use: who needs to hear that new sessions moved, or that
/// a login is worth moving to. A port of its own — quota alerts don't carry it.
@Mockable
public protocol InUseAnnouncer: Sendable {
    func announce(_ alert: InUseAlert) async
}

/// *In use* news, as an alert carries it: plain values, and the
/// `claudebar://use` link its button opens.
public struct InUseAlert: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// *Switch when low* moved new sessions — the button undoes it.
        case switched
        /// The login in use is low — the button moves new sessions.
        case worthSwitching
    }

    public let kind: Kind
    public let providerName: String
    public let from: String
    public let to: String
    /// What `from` has left, in whole percent.
    public let fromLeft: Int?
    public let toLeft: Int?
    /// The button's link: back to `from` for a switch, on to `to` for a suggestion.
    public let link: URL

    public init(kind: Kind, providerName: String, from: String, to: String, fromLeft: Int?, toLeft: Int?, link: URL) {
        self.kind = kind
        self.providerName = providerName
        self.from = from
        self.to = to
        self.fromLeft = fromLeft
        self.toLeft = toLeft
        self.link = link
    }

    /// The alert for `notice` about `provider`'s logins.
    @MainActor
    public init(_ notice: InUseNotice, of provider: Provider) {
        let (kind, from, to, target): (Kind, Account, Account, Account) = switch notice {
        case let .switched(from, to): (.switched, from, to, from)
        case let .worthSwitching(from, to): (.worthSwitching, from, to, to)
        }
        var link = URLComponents()
        link.scheme = "claudebar"
        link.host = "use"
        link.queryItems = [URLQueryItem(name: "provider", value: provider.id), URLQueryItem(name: "account", value: target.accountId)]
        self.init(kind: kind, providerName: provider.name, from: from.displayName, to: to.displayName,
                  fromLeft: from.snapshot?.lowestQuota.map { Int($0.percentRemaining) },
                  toLeft: to.snapshot?.lowestQuota.map { Int($0.percentRemaining) },
                  link: link.url!)
    }
}
