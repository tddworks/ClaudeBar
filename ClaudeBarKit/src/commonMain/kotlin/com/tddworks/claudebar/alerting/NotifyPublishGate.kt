package com.tddworks.claudebar.alerting

/** What each surface is showing, and when each was last written (Unix seconds). */
internal data class NotifyPublishRecord(
    val payload: NotifyPayload,
    val tileAtSeconds: Double? = null,
    val gaugeAtSeconds: Double? = null,
    val screenTileAtSeconds: Double? = null,
) {
    /**
     * The record after a publish, keeping the content and time of every surface not written.
     * Storing the whole payload would file a held-back gauge as sent, and the gate would then
     * see no change when the gauge's own interval came round.
     */
    fun updated(payload: NotifyPayload, decision: NotifyPublishDecision, nowSeconds: Double): NotifyPublishRecord =
        NotifyPublishRecord(
            payload = NotifyPayload(
                tile = if (decision.publishesTile) payload.tile else this.payload.tile,
                gauge = if (decision.publishesGauge) payload.gauge else this.payload.gauge,
                screenTile = if (decision.publishesScreenTile) payload.screenTile else this.payload.screenTile,
            ),
            tileAtSeconds = if (decision.publishesTile) nowSeconds else tileAtSeconds,
            gaugeAtSeconds = if (decision.publishesGauge) nowSeconds else gaugeAtSeconds,
            screenTileAtSeconds = if (decision.publishesScreenTile) nowSeconds else screenTileAtSeconds,
        )
}

/** Which surfaces a publish writes. */
internal data class NotifyPublishDecision(
    val publishesTile: Boolean,
    val publishesGauge: Boolean,
    val publishesScreenTile: Boolean = false,
) {
    val publishesNothing: Boolean get() = !publishesTile && !publishesGauge && !publishesScreenTile

    companion object {
        val nothing = NotifyPublishDecision(publishesTile = false, publishesGauge = false, publishesScreenTile = false)
    }
}

/**
 * When a payload is worth a request. Quotas move every refresh and the countdown every minute,
 * so "whenever it differs" would mean a request per refresh forever. On top of the difference:
 * a minimum gap per surface (iOS redraws a widget about every quarter hour however often it is
 * pushed), and a keep-alive for the tile and the Home Screen tile (the gateway ends a
 * progress-only Live Activity after two hours without an update, and a screen widget goes
 * stale two hours after its last write). Pure: "now" is a parameter.
 */
internal class NotifyPublishGate(
    private val tileIntervalSeconds: Double = DEFAULT_TILE_INTERVAL,
    private val gaugeIntervalSeconds: Double = DEFAULT_GAUGE_INTERVAL,
    private val screenTileIntervalSeconds: Double = DEFAULT_SCREEN_TILE_INTERVAL,
    private val keepAliveIntervalSeconds: Double = DEFAULT_KEEP_ALIVE_INTERVAL,
) {
    fun decide(payload: NotifyPayload, since: NotifyPublishRecord?, nowSeconds: Double): NotifyPublishDecision =
        NotifyPublishDecision(
            publishesTile = publishesTile(payload, since, nowSeconds),
            publishesGauge = publishesGauge(payload, since, nowSeconds),
            publishesScreenTile = publishesScreenTile(payload, since, nowSeconds),
        )

    private fun publishesTile(payload: NotifyPayload, record: NotifyPublishRecord?, now: Double): Boolean {
        val tile = payload.tile ?: return false
        val lastAt = record?.tileAtSeconds ?: return true
        val elapsed = now - lastAt
        if (elapsed >= keepAliveIntervalSeconds) return true
        return tile != record.payload.tile && elapsed >= tileIntervalSeconds
    }

    /** Takes the keep-alive too: two hours after the last write the phone dims it as stale. */
    private fun publishesScreenTile(payload: NotifyPayload, record: NotifyPublishRecord?, now: Double): Boolean {
        val screenTile = payload.screenTile ?: return false
        val lastAt = record?.screenTileAtSeconds ?: return true
        val elapsed = now - lastAt
        if (elapsed >= keepAliveIntervalSeconds) return true
        return screenTile != record.payload.screenTile && elapsed >= screenTileIntervalSeconds
    }

    private fun publishesGauge(payload: NotifyPayload, record: NotifyPublishRecord?, now: Double): Boolean {
        val gauge = payload.gauge ?: return false
        val lastAt = record?.gaugeAtSeconds ?: return true
        return gauge != record.payload.gauge && now - lastAt >= gaugeIntervalSeconds
    }

    companion object {
        /** The tile is a push, so it can be prompt. */
        const val DEFAULT_TILE_INTERVAL = 60.0

        /** The widget is a poll on iOS's quarter hour. */
        const val DEFAULT_GAUGE_INTERVAL = 15 * 60.0

        /** The Home Screen tile is a poll like the gauge. */
        const val DEFAULT_SCREEN_TILE_INTERVAL = 15 * 60.0

        /** Comfortably inside both two-hour deadlines it has to beat. */
        const val DEFAULT_KEEP_ALIVE_INTERVAL = 90 * 60.0
    }
}
