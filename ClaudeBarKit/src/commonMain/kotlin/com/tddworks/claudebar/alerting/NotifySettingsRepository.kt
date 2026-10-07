package com.tddworks.claudebar.alerting

/** Defaults for the Notify! integration. */
internal object NotifyConstants {
    /** Off until a device is linked: the feature sends data to a third party. */
    const val DEFAULT_ENABLED = false

    /** Both Lock Screen surfaces are on once the feature is; each switches off on its own. */
    const val DEFAULT_LIVE_ACTIVITY_ENABLED = true
    const val DEFAULT_WIDGET_ENABLED = true

    /**
     * On although the gateway ships it behind a kill switch: a 503 reads as "not yet", and off
     * would mean nobody sees the surface the day it is switched on.
     */
    const val DEFAULT_SCREEN_WIDGET_ENABLED = true
}

/**
 * Settings for publishing to a Notify! device. A destination's own repository, beside
 * `HookSettingsRepository` — Notify! is written to, not read from, so no provider setting
 * applies. The device token is a secret: it goes to the credential store, never settings.json.
 */
public interface NotifySettingsRepository {
    fun isNotifyEnabled(): Boolean
    fun setNotifyEnabled(enabled: Boolean)

    /** Empty when nothing is linked. */
    fun notifyDeviceId(): String
    fun setNotifyDeviceId(deviceId: String)

    fun saveNotifyDeviceToken(token: String)
    fun notifyDeviceToken(): String?
    fun deleteNotifyDeviceToken(): Boolean
    fun hasNotifyDeviceToken(): Boolean

    /**
     * Whether the token is in the Keychain rather than the fallback store. The Keychain refuses
     * an ad-hoc-signed (local) build, so the pane asks to say where the token really is.
     */
    fun notifyDeviceTokenIsSecure(): Boolean

    fun isNotifyLiveActivityEnabled(): Boolean
    fun setNotifyLiveActivityEnabled(enabled: Boolean)

    fun isNotifyWidgetEnabled(): Boolean
    fun setNotifyWidgetEnabled(enabled: Boolean)

    /** The Home Screen widget: the Live Activity's content, but it stays. */
    fun isNotifyScreenWidgetEnabled(): Boolean
    fun setNotifyScreenWidgetEnabled(enabled: Boolean)

    /** Which provider the gauge shows; empty means "whichever needs attention most". */
    fun notifyGaugeProviderId(): String
    fun setNotifyGaugeProviderId(providerId: String)

    /** Which window the gauge shows; empty means automatic. */
    fun notifyGaugeQuotaKey(): String
    fun setNotifyGaugeQuotaKey(quotaKey: String)

    /** The handle of the Live Activity ClaudeBar started, so updates address that exact tile. */
    fun notifyActivityId(): String?
    fun setNotifyActivityId(activityId: String?)

    fun notifyWidgetId(): String?
    fun setNotifyWidgetId(widgetId: String?)

    fun notifyScreenWidgetId(): String?
    fun setNotifyScreenWidgetId(screenWidgetId: String?)

    /** The saved credentials as one value; null when either half is missing or malformed. */
    fun notifyDeviceLink(): NotifyDeviceLink? {
        val token = notifyDeviceToken() ?: return null
        return NotifyDeviceLink.of(notifyDeviceId(), token)
    }

    /**
     * Stores a link, keeping the surface handles when it names the same device. Handles belong
     * to a device, not a credential: a re-save or a rotated token is the same phone, and
     * clearing them would orphan its tile and widgets and make the next publish create
     * duplicates. Only a different device id clears them.
     */
    fun saveNotifyDeviceLink(link: NotifyDeviceLink) {
        if (notifyDeviceId() != link.deviceId) {
            setNotifyActivityId(null)
            setNotifyWidgetId(null)
            setNotifyScreenWidgetId(null)
        }
        setNotifyDeviceId(link.deviceId)
        saveNotifyDeviceToken(link.token)
    }

    fun notifyGaugeSelection(): NotifyGaugeSelection =
        NotifyGaugeSelection(providerId = notifyGaugeProviderId(), quotaKey = notifyGaugeQuotaKey())
}
