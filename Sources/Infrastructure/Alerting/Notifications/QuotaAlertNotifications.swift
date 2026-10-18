import Domain
import Foundation

/// *Quota alerts* as a notification: *Claude · work is below 35%*, *34% left.*
public final class QuotaAlertNotifications: QuotaAlertAnnouncer, @unchecked Sendable {
    /// The category of quota-alert notifications.
    public static let category = "QUOTA_ALERT_PERCENT"

    private let alertSender: AlertSender

    public init() {
        self.alertSender = SystemAlertSender()
    }

    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    public func announce(_ alert: QuotaAlert) async {
        do {
            try await alertSender.send(title: "\(alert.login) is below \(alert.below)%",
                                       body: "\(alert.left)% left.", categoryIdentifier: Self.category)
        } catch {
            AppLog.notifications.error("Failed to send a quota alert: \(error.localizedDescription)")
        }
    }
}
