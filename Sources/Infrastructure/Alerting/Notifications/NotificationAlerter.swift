import Foundation
import Domain
import Mockable

// MARK: - Internal Protocol (for testability)

/// Internal protocol for sending system alerts. Enables testing without UNUserNotificationCenter.
@Mockable
protocol AlertSender: Sendable {
    func requestPermission() async -> Bool
    func send(title: String, body: String, categoryIdentifier: String) async throws
    /// A notification with one button, which opens `link`.
    func send(title: String, body: String, categoryIdentifier: String, button: String, link: URL) async throws
}

// MARK: - NotificationAlerter

/// *Status alerts* as a notification: *Claude · work Quota Alert*, *Your
/// Claude · work quota is critically low! Save important work.* Whether to
/// tell is `StatusAlerts`'; this only words it.
public final class NotificationAlerter: AlertDestination, @unchecked Sendable {

    private let alertSender: AlertSender

    /// Public initializer - uses system alerts
    public init() {
        self.alertSender = SystemAlertSender()
    }

    /// Internal initializer for testing
    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    /// Requests permission to send notifications.
    public func requestPermission() async -> Bool {
        AppLog.notifications.debug("Requesting alert permission...")
        let granted = await alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: \(granted ? "granted" : "denied")")
        return granted
    }

    public func announce(_ alert: Alert) async {
        guard case .status(let alert) = alert else { return }
        AppLog.notifications.notice("Sending a status alert for \(alert.providerId): \(alert.now)")
        do {
            try await alertSender.send(title: "\(alert.login) Quota Alert",
                                       body: Self.body(for: alert.now, login: alert.login),
                                       categoryIdentifier: "QUOTA_ALERT")
        } catch {
            AppLog.notifications.error("Failed to send alert: \(error.localizedDescription)")
        }
    }

    static func body(for status: QuotaStatus, login: String) -> String {
        switch status {
        case .warning:
            "Your \(login) quota is running low. Consider pacing your usage."
        case .critical:
            "Your \(login) quota is critically low! Save important work."
        case .depleted:
            "Your \(login) quota is depleted. Usage may be blocked."
        case .healthy:
            "Your \(login) quota has recovered."
        }
    }
}
