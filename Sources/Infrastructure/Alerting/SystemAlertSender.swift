import Foundation
import UserNotifications

/// System alert sender using macOS UNUserNotificationCenter.
/// This is excluded from code coverage as it's a pure adapter for system APIs.
public final class SystemAlertSender: AlertSender, @unchecked Sendable {

    public init() {}

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            AppLog.notifications.warning("No bundle identifier - alerts unavailable")
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    func requestPermission() async -> Bool {
        guard let center = notificationCenter else {
            AppLog.notifications.error("Notification center unavailable")
            return false
        }

        let settings = await center.notificationSettings()
        AppLog.notifications.info("Current alert permission status: \(settings.authorizationStatus.rawValue)")

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            AppLog.notifications.info("Alerts already authorized")
            return true
        case .denied:
            AppLog.notifications.warning("Alerts denied by user - check System Settings > Notifications > ClaudeBar")
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                AppLog.notifications.info("Alert authorization result: \(granted)")
                return granted
            } catch {
                AppLog.notifications.error("Alert authorization error: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            AppLog.notifications.warning("Unknown alert authorization status")
            return false
        }
    }

    public func send(title: String, body: String, categoryIdentifier: String) async throws {
        guard let center = notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try await center.add(request)
    }

    /// The button's id — the app opens `userInfo["link"]` when it is pressed.
    public static let linkAction = "OPEN_LINK"

    func send(title: String, body: String, categoryIdentifier: String, button: String, link: URL) async throws {
        guard let center = notificationCenter else { return }
        // A category's buttons are fixed, so each button title gets its own.
        let category = "\(categoryIdentifier).\(button)"
        var categories = await center.notificationCategories()
        if !categories.contains(where: { $0.identifier == category }) {
            categories.insert(UNNotificationCategory(
                identifier: category,
                actions: [UNNotificationAction(identifier: Self.linkAction, title: button, options: [])],
                intentIdentifiers: []
            ))
            center.setNotificationCategories(categories)
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["link": link.absoluteString]
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
