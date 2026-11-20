import Foundation
import Quotas
import DataSources
import Providers
import Monitoring
import Diagnostics

/// This Mac's notifications — a destination for both kinds of alert, in the
/// words the person has always read: *Claude · work is below 35%*, *34% left.*;
/// *Claude · work Quota Alert*, *Your Claude · work quota is critically low!
/// Save important work.* Whether to tell is the deciders'; this only words it.
final class SystemNotifications: Notifications, @unchecked Sendable {
    /// The category of quota-alert notifications.
    static let quotaAlertCategory = "QUOTA_ALERT_PERCENT"
    /// The category of status-alert notifications.
    static let statusAlertCategory = "QUOTA_ALERT"
    /// The category of signed-out notifications.
    static let signedOutCategory = "SIGNED_OUT"

    private let alertSender: AlertSender

    init() {
        self.alertSender = SystemAlertSender()
    }

    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    /// Asks macOS to let ClaudeBar show notifications.
    func requestPermission() async -> Bool {
        AppLog.notifications.debug("Requesting alert permission...")
        let granted = await alertSender.requestPermission()
        AppLog.notifications.info("Alert permission: \(granted ? "granted" : "denied")")
        return granted
    }

    func announce(_ alert: Alert) async {
        let (title, body, category) = switch alert {
        case .quota(let alert):
            ("\(alert.login) is below \(alert.below)%", "\(alert.left)% left.", Self.quotaAlertCategory)
        case .status(let alert):
            ("\(alert.login) Quota Alert", Self.body(for: alert.now, login: alert.login), Self.statusAlertCategory)
        case .signedOut(let alert):
            ("\(alert.login) signed out", alert.hint ?? "Sign in again to see its usage.", Self.signedOutCategory)
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
