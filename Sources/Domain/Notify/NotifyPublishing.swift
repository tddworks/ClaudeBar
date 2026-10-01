import Foundation
import Mockable

/// Publishing quota state to a linked Notify! device.
///
/// The Domain side of the feature: what ClaudeBar can ask for, in Domain value
/// types, with no idea that HTTP exists. `NotifyGatewayClient` in Infrastructure
/// is the implementation.
///
/// Both write methods take the handle of the thing they last wrote and return
/// the handle to store next time. That is what keeps ClaudeBar from touching a
/// tile or widget the user created for something else: a nil handle means
/// "create your own", and every later write addresses that one by id.
@Mockable
public protocol NotifyPublishing: Sendable {
    /// Starts a Live Activity, or updates the one `activityId` names.
    /// - Returns: the activity id to store for the next update.
    func publishTile(
        _ tile: NotifyTile,
        link: NotifyDeviceLink,
        activityId: String?
    ) async throws -> String

    /// Creates the widget, or updates the one `widgetId` names.
    /// - Returns: the widget id to store for the next update.
    func publishGauge(
        _ gauge: NotifyGauge,
        link: NotifyDeviceLink,
        widgetId: String?
    ) async throws -> String

    /// Creates the Home Screen widget, or updates the one `screenWidgetId`
    /// names.
    ///
    /// Takes a `NotifyTile` rather than a shape of its own: the gateway derives
    /// this route's content contract from the Live Activity module, so the two
    /// surfaces genuinely accept one body.
    /// - Returns: the screen widget id to store for the next update.
    func publishScreenTile(
        _ tile: NotifyTile,
        link: NotifyDeviceLink,
        screenWidgetId: String?
    ) async throws -> String

    /// Ends the Live Activity, optionally leaving it on the Lock Screen for a
    /// while so the final state can be read.
    func endTile(link: NotifyDeviceLink, activityId: String, keepFor: TimeInterval) async throws

    /// Checks a device id and token pair and describes the device it names.
    /// The only user-triggered call, and rate limited to five a minute by the
    /// gateway, so it belongs behind an explicit button and nothing else.
    func deviceInfo(link: NotifyDeviceLink) async throws -> NotifyDeviceInfo
}
