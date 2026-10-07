package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.suspendCancellableCoroutine
import platform.Foundation.NSBundle
import platform.Foundation.NSError
import platform.Foundation.NSUUID
import platform.UserNotifications.UNAuthorizationOptionAlert
import platform.UserNotifications.UNAuthorizationOptionBadge
import platform.UserNotifications.UNAuthorizationOptionSound
import platform.UserNotifications.UNAuthorizationStatusAuthorized
import platform.UserNotifications.UNAuthorizationStatusDenied
import platform.UserNotifications.UNAuthorizationStatusNotDetermined
import platform.UserNotifications.UNAuthorizationStatusProvisional
import platform.UserNotifications.UNMutableNotificationContent
import platform.UserNotifications.UNNotificationAction
import platform.UserNotifications.UNNotificationCategory
import platform.UserNotifications.UNNotificationRequest
import platform.UserNotifications.UNNotificationSettings
import platform.UserNotifications.UNNotificationSound
import platform.UserNotifications.UNUserNotificationCenter
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** [AlertSender] on the system's UNUserNotificationCenter. */
internal class UserNotificationsAlertSender : AlertSender {

    /** Unavailable without a bundle identifier (a bare test binary): alerts then do nothing. */
    private val center: UNUserNotificationCenter?
        get() {
            if (NSBundle.mainBundle.bundleIdentifier == null) {
                AppLog.notifications.warning("No bundle identifier - alerts unavailable")
                return null
            }
            return UNUserNotificationCenter.currentNotificationCenter()
        }

    override suspend fun requestPermission(): Boolean {
        val center = center ?: run {
            AppLog.notifications.error("Notification center unavailable")
            return false
        }
        val status = suspendCancellableCoroutine { continuation ->
            center.getNotificationSettingsWithCompletionHandler { settings: UNNotificationSettings? ->
                continuation.resume(settings?.authorizationStatus)
            }
        }
        AppLog.notifications.info("Current alert permission status: $status")
        return when (status) {
            UNAuthorizationStatusAuthorized, UNAuthorizationStatusProvisional -> {
                AppLog.notifications.info("Alerts already authorized")
                true
            }
            UNAuthorizationStatusDenied -> {
                AppLog.notifications.warning("Alerts denied by user - check System Settings > Notifications > ClaudeBar")
                false
            }
            UNAuthorizationStatusNotDetermined -> suspendCancellableCoroutine { continuation ->
                center.requestAuthorizationWithOptions(
                    UNAuthorizationOptionAlert or UNAuthorizationOptionSound or UNAuthorizationOptionBadge,
                ) { granted, error ->
                    if (error != null) {
                        AppLog.notifications.error("Alert authorization error: ${error.localizedDescription}")
                        continuation.resume(false)
                    } else {
                        AppLog.notifications.info("Alert authorization result: $granted")
                        continuation.resume(granted)
                    }
                }
            }
            else -> {
                AppLog.notifications.warning("Unknown alert authorization status")
                false
            }
        }
    }

    override suspend fun send(title: String, body: String, categoryIdentifier: String) {
        val center = center ?: return
        val content = UNMutableNotificationContent().apply {
            setTitle(title)
            setBody(body)
            setSound(UNNotificationSound.defaultSound)
            setCategoryIdentifier(categoryIdentifier)
        }
        add(center, content)
    }

    override suspend fun send(title: String, body: String, categoryIdentifier: String, button: String, link: String) {
        val center = center ?: return
        // A category's buttons are fixed, so each button title gets its own.
        val category = "$categoryIdentifier.$button"
        val categories = suspendCancellableCoroutine { continuation ->
            center.getNotificationCategoriesWithCompletionHandler { set -> continuation.resume(set.orEmpty()) }
        }
        if (categories.none { (it as? UNNotificationCategory)?.identifier == category }) {
            val action = UNNotificationAction.actionWithIdentifier(LINK_ACTION, button, 0u)
            val added = UNNotificationCategory.categoryWithIdentifier(category, listOf(action), emptyList<Any>(), 0u)
            center.setNotificationCategories(categories + added)
        }
        val content = UNMutableNotificationContent().apply {
            setTitle(title)
            setBody(body)
            setSound(UNNotificationSound.defaultSound)
            setCategoryIdentifier(category)
            setUserInfo(mapOf<Any?, Any?>("link" to link))
        }
        add(center, content)
    }

    private suspend fun add(center: UNUserNotificationCenter, content: UNMutableNotificationContent) {
        val request = UNNotificationRequest.requestWithIdentifier(NSUUID().UUIDString, content, null)
        suspendCancellableCoroutine { continuation ->
            center.addNotificationRequest(request) { error: NSError? ->
                if (error == null) continuation.resume(Unit)
                else continuation.resumeWithException(IllegalStateException(error.localizedDescription))
            }
        }
    }

    companion object {
        /** The button's id: the app opens `userInfo["link"]` when it is pressed. */
        const val LINK_ACTION = AlertActions.OPEN_LINK
    }
}
