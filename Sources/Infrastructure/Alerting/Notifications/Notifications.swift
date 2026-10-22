import Foundation
import Domain

/// This Mac's notifications — a destination for both kinds of alert, in the
/// words the person has always read: *Claude · work is below 35%*, *34% left.*;
/// *Claude · work Quota Alert*, *Your Claude · work quota is critically low!
/// Save important work.* Whether to tell is the deciders'; this only words it.
public final class Notifications: AlertDestination, @unchecked Sendable {
    /// The category of quota-alert notifications.
    public static let quotaAlertCategory = "QUOTA_ALERT_PERCENT"
    /// The category of status-alert notifications.
    public static let statusAlertCategory = "QUOTA_ALERT"

    private let alertSender: AlertSender

    public init() {
        self.alertSender = SystemAlertSender()
    }

    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    /// Asks macOS to let ClaudeBar show notifications.
    public func requestPermission() async -> Bool {
        AppLog.notifications.debug("Requesting alert permission...")
        let granted = await alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: \(granted ? "granted" : "denied")")
        return granted
    }

    public func announce(_ alert: Alert) async {
        let (title, body, category) = switch alert {
        case .quota(let alert):
            ("\(alert.login) is below \(alert.below)%", "\(alert.left)% left.", Self.quotaAlertCategory)
        case .status(let alert):
            ("\(alert.login) Quota Alert", Self.body(for: alert.now, login: alert.login), Self.statusAlertCategory)
        }
        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: category)
        } catch {
            AppLog.notifications.error("Failed to send an alert: \(error.localizedDescription)")
        }
    }

    private static func body(for status: QuotaStatus, login: String) -> String {
        switch status {
        case .warning: "Your \(login) quota is running low. Consider pacing your usage."
        case .critical: "Your \(login) quota is critically low! Save important work."
        case .depleted: "Your \(login) quota is depleted. Usage may be blocked."
        case .healthy: "Your \(login) quota has recovered."
        }
    }
}
