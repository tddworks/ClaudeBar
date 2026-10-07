package com.tddworks.claudebar.alerting

/** The system's notifications, behind a port so nothing but its adapter touches UserNotifications. */
internal interface AlertSender {
    /** Asks once; true when the person allowed alerts (or already had). */
    suspend fun requestPermission(): Boolean

    suspend fun send(title: String, body: String, categoryIdentifier: String)

    /** A notification with one button, which opens [link]. */
    suspend fun send(title: String, body: String, categoryIdentifier: String, button: String, link: String)
}
