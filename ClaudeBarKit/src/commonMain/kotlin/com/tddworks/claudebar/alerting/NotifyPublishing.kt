package com.tddworks.claudebar.alerting

/**
 * Publishing quota state to a linked Notify! device, with no idea that HTTP exists;
 * [NotifyGatewayClient] is the adapter. Each write takes the handle of what it last wrote and
 * returns the handle to keep: null means "create your own", so ClaudeBar never touches a tile
 * or widget the person made for something else. Failures throw [NotifyPublishError].
 */
internal interface NotifyPublishing {
    /** Starts a Live Activity, or updates the one [activityId] names; returns the id to keep. */
    suspend fun publishTile(tile: NotifyTile, link: NotifyDeviceLink, activityId: String?): String

    /** Creates the widget, or updates the one [widgetId] names; returns the id to keep. */
    suspend fun publishGauge(gauge: NotifyGauge, link: NotifyDeviceLink, widgetId: String?): String

    /**
     * Creates the Home Screen widget, or updates the one [screenWidgetId] names. Takes a
     * [NotifyTile]: the gateway derives this route's contract from the Live Activity's, so both
     * accept one body.
     */
    suspend fun publishScreenTile(tile: NotifyTile, link: NotifyDeviceLink, screenWidgetId: String?): String

    /** Ends the Live Activity, leaving it on the Lock Screen for [keepForSeconds] so the end can be read. */
    suspend fun endTile(link: NotifyDeviceLink, activityId: String, keepForSeconds: Double)

    /**
     * Checks an id and token and describes the device. Rate limited by the gateway to five a
     * minute, so only an explicit button calls it.
     */
    suspend fun deviceInfo(link: NotifyDeviceLink): NotifyDeviceInfo
}
