import Foundation
import Mockable

/// Where each product's `WhenEmpty` is saved: `providers.<id>.restWhenEmpty`
/// in settings.json. `nil` means the person never asked, or turned the card
/// off. A feature's own repository, beside `QuotaAlertSettingsRepository`,
/// never one of a definition's settings.
@Mockable
public protocol RestWhenEmptyRepository: Sendable {
    func whenEmpty(forProvider id: String) -> WhenEmpty?
    func setWhenEmpty(_ state: WhenEmpty?, forProvider id: String)
}

/// Who needs to hear that a product rests, or is back. A port of its own:
/// the quota and status alerts don't carry it, and a webhook's kinds don't
/// either.
@Mockable
public protocol RestWhenEmptyAnnouncer: Sendable {
    func announce(_ notice: RestNotice) async
}

/// *Rest when empty* news, as plain values. The button's link is the App's
/// to build: `URLSchemeAction` owns `claudebar://` both ways.
public struct RestNotice: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Every login ran out: it is dimmed now, and *Show anyway* undoes that.
        case resting
        /// A refresh showed room again.
        case back
    }

    public let kind: Kind
    /// The product, as the person named it.
    public let productName: String
    public let providerId: String

    public init(kind: Kind, productName: String, providerId: String) {
        self.kind = kind
        self.productName = productName
        self.providerId = providerId
    }
}
