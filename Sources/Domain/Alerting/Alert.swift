import Foundation
import Mockable

/// What an alert decider decided: a login fell below the person's percent, or
/// its status got worse. Either names the login as the lineup does, and its
/// provider, so a destination can judge its scope
/// ([design](docs/features/alerting/webhooks/design.md)).
public enum Alert: Sendable, Equatable {
    case quota(QuotaAlert)
    case status(StatusAlert)
    case signedOut(SignedOutAlert)

    /// The login, as the lineup names it.
    public var login: String {
        switch self {
        case .quota(let alert): alert.login
        case .status(let alert): alert.login
        case .signedOut(let alert): alert.login
        }
    }

    /// The product the login belongs to.
    public var providerId: String {
        switch self {
        case .quota(let alert): alert.providerId
        case .status(let alert): alert.providerId
        case .signedOut(let alert): alert.providerId
        }
    }
}

/// Who hears an alert: this Mac's notifications, the person's webhooks. A
/// destination never decides *whether* a login is low — `QuotaAlerts` and
/// `StatusAlerts` did — only what it does with what it is told.
@Mockable
public protocol AlertDestination: Sendable {
    func announce(_ alert: Alert) async
}

/// Every destination, told every alert in turn — the one fan-out both
/// deciders tell, built in the composition root.
public struct AlertDestinations: AlertDestination {
    private let destinations: [any AlertDestination]

    public init(_ destinations: [any AlertDestination]) {
        self.destinations = destinations
    }

    public func announce(_ alert: Alert) async {
        for destination in destinations {
            await destination.announce(alert)
        }
    }
}
