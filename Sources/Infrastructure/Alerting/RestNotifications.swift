import Domain
import Foundation

/// *Rest when empty* news as a notification: the product rests, with a
/// *Show anyway* button, and it is back. The button's link comes from the
/// App, which owns `claudebar://` both ways.
public final class RestNotifications: RestWhenEmptyAnnouncer, @unchecked Sendable {
    /// The category of *Rest when empty* notifications.
    public static let category = "REST_WHEN_EMPTY"

    private let alertSender: AlertSender
    private let showAnywayLink: @Sendable (_ providerId: String) -> URL

    public convenience init(showAnywayLink: @escaping @Sendable (_ providerId: String) -> URL) {
        self.init(alertSender: SystemAlertSender(), showAnywayLink: showAnywayLink)
    }

    init(alertSender: AlertSender, showAnywayLink: @escaping @Sendable (_ providerId: String) -> URL) {
        self.alertSender = alertSender
        self.showAnywayLink = showAnywayLink
    }

    public func announce(_ notice: RestNotice) async {
        do {
            switch notice.kind {
            case .resting:
                try await alertSender.send(
                    title: "\(notice.productName) is resting",
                    body: "Every login has run out, so it is dimmed until a refresh shows room.",
                    categoryIdentifier: Self.category,
                    button: "Show anyway", link: showAnywayLink(notice.providerId))
            case .back:
                try await alertSender.send(title: "\(notice.productName) is back",
                                           body: "A reset gave it room again.",
                                           categoryIdentifier: Self.category)
            }
        } catch {
            AppLog.notifications.error("Failed to send the rest-when-empty notification: \(error.localizedDescription)")
        }
    }
}
