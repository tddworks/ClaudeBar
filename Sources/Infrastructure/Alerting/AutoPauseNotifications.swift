import Domain
import Foundation

/// *Auto-pause* news as a notification: the product turned itself off — with
/// a *Turn Back On* button that opens the notice's `claudebar://enable`
/// link — and when the reset turned it back on.
public final class AutoPauseNotifications: AutoPauseAnnouncer, @unchecked Sendable {
    /// The category of *Auto-pause* notifications.
    public static let category = "AUTO_PAUSE"

    private let alertSender: AlertSender

    public init() {
        self.alertSender = SystemAlertSender()
    }

    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    public func announce(_ notice: AutoPauseNotice) async {
        let (title, body): (String, String) = switch notice.kind {
        case .turnedOff:
            ("\(notice.productName) ran out",
             "Every login is empty, so its switch is off until the next reset. ClaudeBar will turn it back on when a refresh shows room again.")
        case .turnedOn:
            ("\(notice.productName) is back",
             "A reset gave it room again, so its switch is on.")
        }
        do {
            if notice.kind == .turnedOff {
                try await alertSender.send(title: title, body: body, categoryIdentifier: Self.category,
                                           button: "Turn Back On", link: notice.link)
            } else {
                try await alertSender.send(title: title, body: body, categoryIdentifier: Self.category)
            }
        } catch {
            AppLog.notifications.error("Failed to send the auto-pause notification: \(error.localizedDescription)")
        }
    }
}
