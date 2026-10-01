import Foundation

/// Defaults for the Notify! integration.
public enum NotifyConstants {
    /// Off until the user links a device. The feature sends data to a third
    /// party service, so it can never be on by default.
    public static let defaultEnabled = false

    /// Both surfaces are on once the feature itself is on: a user who linked a
    /// device wants to see their quota, and each can be switched off separately.
    public static let defaultLiveActivityEnabled = true
    public static let defaultWidgetEnabled = true

    /// The Home Screen widget ships behind a server side kill switch, so a
    /// ClaudeBar that supports it can meet a gateway that is not serving it yet.
    /// On by default anyway: a 503 is handled as "not yet" rather than as an
    /// error, and leaving it off would mean nobody sees the surface on the day
    /// it is switched on.
    public static let defaultScreenWidgetEnabled = true
}

/// Settings for publishing quota state to a Notify! device.
///
/// Standalone protocol rather than a `ProviderSettingsRepository` sub-protocol:
/// Notify! is not a provider ClaudeBar reads a quota from, it is a destination
/// ClaudeBar writes to, so none of the provider vocabulary (enable in the
/// popover, custom card URL, probe mode) applies. Mirrors
/// `HookSettingsRepository`, the other feature that is a peer of the providers
/// rather than one of them.
///
/// The device token is a secret and goes to the Keychain-backed credential
/// store, never to `~/.claudebar/settings.json`.
public protocol NotifySettingsRepository: Sendable {
    /// Whether ClaudeBar publishes to Notify! at all.
    func isNotifyEnabled() -> Bool
    func setNotifyEnabled(_ enabled: Bool)

    /// The linked device id, empty when nothing is linked.
    func notifyDeviceId() -> String
    func setNotifyDeviceId(_ deviceId: String)

    /// The per device token, held in the secure credential store when the
    /// platform will take it.
    func saveNotifyDeviceToken(_ token: String)
    func notifyDeviceToken() -> String?
    @discardableResult
    func deleteNotifyDeviceToken() -> Bool
    func hasNotifyDeviceToken() -> Bool

    /// Whether the stored token is in the Keychain rather than the fallback
    /// store.
    ///
    /// The Keychain refuses an ad-hoc signed build, which is every build made
    /// locally, so a token can legitimately end up in the app credential store
    /// instead. The pane asks so that it can say where the token actually is,
    /// rather than showing a badge that implies the stronger answer.
    func notifyDeviceTokenIsSecure() -> Bool

    /// Whether the Lock Screen Live Activity is published.
    func isNotifyLiveActivityEnabled() -> Bool
    func setNotifyLiveActivityEnabled(_ enabled: Bool)

    /// Whether the Lock Screen widget gauge is published.
    func isNotifyWidgetEnabled() -> Bool
    func setNotifyWidgetEnabled(_ enabled: Bool)

    /// Whether the Home Screen widget is published. It carries the same content
    /// as the Live Activity, and unlike it, it stays.
    func isNotifyScreenWidgetEnabled() -> Bool
    func setNotifyScreenWidgetEnabled(_ enabled: Bool)

    /// Which provider the widget gauge shows. Empty means "whichever quota
    /// needs attention most".
    func notifyGaugeProviderId() -> String
    func setNotifyGaugeProviderId(_ providerId: String)

    /// Which quota window the widget gauge shows. Empty means automatic.
    func notifyGaugeQuotaKey() -> String
    func setNotifyGaugeQuotaKey(_ quotaKey: String)

    /// The handle of the Live Activity ClaudeBar started, so later updates
    /// address that exact tile and never one the user started elsewhere.
    func notifyActivityId() -> String?
    func setNotifyActivityId(_ activityId: String?)

    /// The handle of the widget ClaudeBar created, for the same reason.
    func notifyWidgetId() -> String?
    func setNotifyWidgetId(_ widgetId: String?)

    /// The handle of the Home Screen widget ClaudeBar created.
    func notifyScreenWidgetId() -> String?
    func setNotifyScreenWidgetId(_ screenWidgetId: String?)
}

public extension NotifySettingsRepository {
    /// The saved credentials as one value, or nil when either half is missing
    /// or malformed. The single place the rest of the app asks "are we linked".
    func notifyDeviceLink() -> NotifyDeviceLink? {
        guard let token = notifyDeviceToken() else { return nil }
        return NotifyDeviceLink(deviceId: notifyDeviceId(), token: token)
    }

    /// Stores a link, keeping the surface handles when it names the same device.
    ///
    /// The handles are owned by a device, not by a credential. Pressing Save
    /// twice, or re-saving after rotating a token, names the same phone, and the
    /// tile and the two widgets already standing on it are still ours: clearing
    /// their handles would orphan them and make the next publish create a second
    /// set beside them, which on a Home Screen is a duplicate the user has to go
    /// and remove by hand. Only a different device id invalidates them, and then
    /// they must go, because they name surfaces on a phone this link can no
    /// longer write to.
    ///
    /// The device id is the comparison rather than the whole link for that same
    /// reason: a rotated token is the same phone.
    func saveNotifyDeviceLink(_ link: NotifyDeviceLink) {
        if notifyDeviceId() != link.deviceId {
            setNotifyActivityId(nil)
            setNotifyWidgetId(nil)
            setNotifyScreenWidgetId(nil)
        }

        setNotifyDeviceId(link.deviceId)
        saveNotifyDeviceToken(link.token)
    }

    /// Which quota window the gauge should show.
    func notifyGaugeSelection() -> NotifyGaugeSelection {
        NotifyGaugeSelection(
            providerId: notifyGaugeProviderId(),
            quotaKey: notifyGaugeQuotaKey()
        )
    }
}
