package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.storage.CredentialRepository
import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * Notify!'s settings in settings.json under `notify.*`, and its device token in [secure] (the
 * Keychain) — or, when the Keychain refuses it, in [fallback]: the app's UserDefaults
 * credential store, which already holds other providers' tokens. A signed build stores the
 * token in the Keychain and the fallback stays empty.
 */
internal class NotifySettings(
    private val settings: SettingsFile,
    private val secure: CredentialRepository,
    private val fallback: CredentialRepository,
) : NotifySettingsRepository {

    override fun isNotifyEnabled(): Boolean = settings.flag("notify.enabled") ?: NotifyConstants.DEFAULT_ENABLED
    override fun setNotifyEnabled(enabled: Boolean) = settings.write("notify.enabled", JsonPrimitive(enabled))

    override fun notifyDeviceId(): String = settings.string("notify.deviceId") ?: ""
    override fun setNotifyDeviceId(deviceId: String) = settings.write("notify.deviceId", JsonPrimitive(deviceId))

    // Straight to the secure store, with no migration: Notify! never kept a plaintext token.
    override fun saveNotifyDeviceToken(token: String) {
        // Pasted tokens carry stray whitespace; an empty field is the person unlinking, not a
        // blank secret that would look linked and then fail with a 403.
        val trimmed = token.trim()
        if (trimmed.isEmpty()) {
            deleteNotifyDeviceToken()
            return
        }
        secure.save(trimmed, TOKEN_KEY)

        // Prove it landed: an ad-hoc-signed build's Keychain refuses reads and writes alike
        // (errSecAuthFailed) while every call looks like success.
        if (secure.get(TOKEN_KEY) == trimmed) {
            // A build that regains the Keychain stops leaving a plaintext copy behind.
            fallback.delete(TOKEN_KEY)
            return
        }
        AppLog.credentials.warning(
            "Notify! token could not be stored in the Keychain, keeping it in the app credential store instead",
        )
        fallback.save(trimmed, TOKEN_KEY)
    }

    override fun notifyDeviceToken(): String? = secure.get(TOKEN_KEY) ?: fallback.get(TOKEN_KEY)

    override fun notifyDeviceTokenIsSecure(): Boolean = secure.get(TOKEN_KEY) != null

    /** Both stores, always: a copy left in the one this build doesn't read would come back. */
    override fun deleteNotifyDeviceToken(): Boolean {
        val fromSecure = secure.delete(TOKEN_KEY)
        val fromFallback = fallback.delete(TOKEN_KEY)
        return fromSecure && fromFallback
    }

    override fun hasNotifyDeviceToken(): Boolean = notifyDeviceToken() != null

    override fun isNotifyLiveActivityEnabled(): Boolean =
        settings.flag("notify.liveActivityEnabled") ?: NotifyConstants.DEFAULT_LIVE_ACTIVITY_ENABLED
    override fun setNotifyLiveActivityEnabled(enabled: Boolean) =
        settings.write("notify.liveActivityEnabled", JsonPrimitive(enabled))

    override fun isNotifyWidgetEnabled(): Boolean =
        settings.flag("notify.widgetEnabled") ?: NotifyConstants.DEFAULT_WIDGET_ENABLED
    override fun setNotifyWidgetEnabled(enabled: Boolean) = settings.write("notify.widgetEnabled", JsonPrimitive(enabled))

    override fun isNotifyScreenWidgetEnabled(): Boolean =
        settings.flag("notify.screenWidgetEnabled") ?: NotifyConstants.DEFAULT_SCREEN_WIDGET_ENABLED
    override fun setNotifyScreenWidgetEnabled(enabled: Boolean) =
        settings.write("notify.screenWidgetEnabled", JsonPrimitive(enabled))

    override fun notifyGaugeProviderId(): String = settings.string("notify.gauge.providerId") ?: ""
    override fun setNotifyGaugeProviderId(providerId: String) =
        settings.write("notify.gauge.providerId", JsonPrimitive(providerId))

    override fun notifyGaugeQuotaKey(): String = settings.string("notify.gauge.quotaKey") ?: ""
    override fun setNotifyGaugeQuotaKey(quotaKey: String) = settings.write("notify.gauge.quotaKey", JsonPrimitive(quotaKey))

    // A handle set to null is removed, never stored as "": that would read back as a handle and
    // aim every later update at a surface that no longer exists.
    override fun notifyActivityId(): String? = settings.string("notify.activityId")
    override fun setNotifyActivityId(activityId: String?) = settings.write("notify.activityId", activityId?.let(::JsonPrimitive))

    override fun notifyWidgetId(): String? = settings.string("notify.widgetId")
    override fun setNotifyWidgetId(widgetId: String?) = settings.write("notify.widgetId", widgetId?.let(::JsonPrimitive))

    override fun notifyScreenWidgetId(): String? = settings.string("notify.screenWidgetId")
    override fun setNotifyScreenWidgetId(screenWidgetId: String?) =
        settings.write("notify.screenWidgetId", screenWidgetId?.let(::JsonPrimitive))

    companion object {
        /** The credential key earlier releases saved the token under. */
        const val TOKEN_KEY = "notify-device-token"
    }
}

/** A yes-or-no setting, or null when absent or not a boolean. */
internal fun SettingsFile.flag(key: String): Boolean? =
    (read(key) as? JsonPrimitive)?.takeUnless { it.isString }?.booleanOrNull
