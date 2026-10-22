import Foundation
import Mockable

/// *Alerting* for Auto-pause: who needs to hear that a product was turned
/// off, or back on. A port of its own — the quota and status alerts don't
/// carry it, and a webhook's kinds don't either.
@Mockable
public protocol AutoPauseAnnouncer: Sendable {
    func announce(_ notice: AutoPauseNotice) async
}

/// *Auto-pause* news, as plain values, with the `claudebar://enable` link
/// its button opens: one click turns the product back on.
public struct AutoPauseNotice: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The product emptied — the button undoes it.
        case turnedOff
        /// The reset came — the product is back on its own.
        case turnedOn
    }

    public let kind: Kind
    /// The product, as the person named it.
    public let productName: String
    public let providerId: String
    /// The button's link: back on, in one click.
    public let link: URL

    public init(kind: Kind, productName: String, providerId: String) {
        self.kind = kind
        self.productName = productName
        self.providerId = providerId
        var components = URLComponents()
        components.scheme = "claudebar"
        components.host = "enable"
        components.queryItems = [URLQueryItem(name: "provider", value: providerId)]
        self.link = components.url!
    }
}
