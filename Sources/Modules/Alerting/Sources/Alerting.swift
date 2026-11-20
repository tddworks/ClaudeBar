import Foundation
import Providers
import Monitoring

/// The factory: Alerting's objects that reach this Mac or the network, handed
/// out as the ports the App composes, so it never names an implementation.
public enum Alerting {
    /// The action of a notification's one button, which opens its link.
    public static let linkAction = SystemAlertSender.linkAction

    /// This Mac's notifications, a destination for every alert.
    public static func makeNotifications() -> any Notifications {
        SystemNotifications()
    }

    /// One notification at a time, for what is not an alert (a session started or ended).
    public static func makeAlertSender() -> any AlertSender {
        SystemAlertSender()
    }

    /// One POST to a webhook's URL.
    public static func makeWebhookSender() -> any WebhookSending {
        WebhookClient()
    }

    /// Notify!'s gateway: tiles, gauges and the linked device.
    public static func makeNotifyGateway() -> any NotifyPublishing {
        NotifyGatewayClient()
    }

    /// Tells the person a product rests, or is back; its button opens `showAnywayLink`.
    public static func makeRestAnnouncer(showAnywayLink: @escaping @Sendable (_ providerId: String) -> URL) -> any RestWhenEmptyAnnouncer {
        RestNotifications(showAnywayLink: showAnywayLink)
    }

    /// Tells the person In use moved new sessions to another login.
    public static func makeInUseAnnouncer() -> any InUseAnnouncer {
        InUseNotifications()
    }
}
