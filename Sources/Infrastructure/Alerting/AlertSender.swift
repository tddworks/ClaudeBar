import Foundation
import Mockable

/// Internal protocol for sending system alerts. Enables testing without UNUserNotificationCenter.
@Mockable
protocol AlertSender: Sendable {
    func requestPermission() async -> Bool
    func send(title: String, body: String, categoryIdentifier: String) async throws
    /// A notification with one button, which opens `link`.
    func send(title: String, body: String, categoryIdentifier: String, button: String, link: URL) async throws
}
