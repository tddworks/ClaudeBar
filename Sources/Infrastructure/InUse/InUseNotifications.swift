import Domain
import Foundation

/// *In use* news as a notification — one button, which opens the alert's
/// `claudebar://use` link: *Use for New Sessions*, or *Undo* after a switch.
public final class InUseNotifications: InUseAnnouncer, @unchecked Sendable {
    /// The category of *In use* notifications.
    public static let category = "IN_USE"

    private let alertSender: AlertSender

    public init() {
        self.alertSender = SystemAlertSender()
    }

    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    public func announce(_ alert: InUseAlert) async {
        let left = { (value: Int?) in value.map { " is at \($0)%" } ?? " is low" }
        let (title, body, button): (String, String, String) = switch alert.kind {
        case .worthSwitching:
            ("\(alert.providerName): \(alert.from)\(left(alert.fromLeft))",
             "\(alert.to) has \(alert.toLeft.map { "\($0)%" } ?? "more") left. Start new terminal sessions on \(alert.to)?",
             "Use for New Sessions")
        case .switched:
            ("New \(alert.providerName) sessions now use \(alert.to)",
             "\(alert.from)\(left(alert.fromLeft)). Sessions already running keep their login.",
             "Undo")
        }
        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: Self.category, button: button, link: alert.link)
        } catch {
            AppLog.notifications.error("Failed to send the In use notification: \(error.localizedDescription)")
        }
    }
}
