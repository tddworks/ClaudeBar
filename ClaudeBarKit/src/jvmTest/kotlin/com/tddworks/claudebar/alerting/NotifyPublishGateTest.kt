package com.tddworks.claudebar.alerting

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NotifyPublishGateTest {
    /** Fixed: every rule is exercised against an explicit elapsed time, never the machine's clock. */
    private val now = 1_700_000_000.0

    private val gate = NotifyPublishGate(tileIntervalSeconds = 60.0, gaugeIntervalSeconds = 900.0, keepAliveIntervalSeconds = 5400.0)

    /** A null argument is a surface the person turned off. */
    private fun payload(tile: String?, gauge: String?, screenTile: String? = null) = NotifyPayload(
        tile = tile?.let { NotifyTile(title = "ClaudeBar", body = it, progress = 42.0) },
        gauge = gauge?.let { NotifyGauge(title = "ClaudeBar", value = it, progress = 42.0) },
        screenTile = screenTile?.let { NotifyTile(title = "ClaudeBar", body = it, progress = 42.0) },
    )

    private fun payload(tileTrailing: String, gaugeValue: String) = NotifyPayload(
        tile = NotifyTile(title = "ClaudeBar", progress = 42.0, trailing = tileTrailing),
        gauge = NotifyGauge(title = "ClaudeBar", value = gaugeValue, unit = "%", progress = 42.0),
    )

    // The first publish

    @Test
    fun `should send both the Live Activity tile and the widget gauge the first time`() {
        val decision = gate.decide(payload("42% left", "42"), since = null, nowSeconds = now)

        assertTrue(decision.publishesTile)
        assertTrue(decision.publishesGauge)
    }

    // Nothing changed

    @Test
    fun `should send nothing when nothing changed and the keep-alive has not come round`() {
        val standing = payload("42% left", "42")
        val record = NotifyPublishRecord(standing, tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(standing, record, now + 3600)

        assertTrue(decision.publishesNothing)
    }

    // The tile

    @Test
    fun `should hold back a changed tile until a minute has passed`() {
        val record = NotifyPublishRecord(payload("42% left", "42"), tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(payload("41% left", "42"), record, now + 30)

        assertFalse(decision.publishesTile)
    }

    @Test
    fun `should send a changed tile once a minute has passed`() {
        val record = NotifyPublishRecord(payload("42% left", "42"), tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(payload("41% left", "42"), record, now + 60)

        assertTrue(decision.publishesTile)
    }

    @Test
    fun `should resend an unchanged tile after ninety minutes so the Live Activity stays alive`() {
        // The gateway ends a progress-only Live Activity after two hours without an update.
        val standing = payload("42% left", "42")
        val record = NotifyPublishRecord(standing, tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(standing, record, now + 5400)

        assertTrue(decision.publishesTile)
    }

    // The gauge

    @Test
    fun `should hold back a changed widget gauge until fifteen minutes have passed`() {
        val record = NotifyPublishRecord(payload("42% left", "42"), tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(payload("42% left", "41"), record, now + 300)

        assertFalse(decision.publishesGauge)
    }

    @Test
    fun `should send a changed widget gauge once fifteen minutes have passed`() {
        val record = NotifyPublishRecord(payload("42% left", "42"), tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(payload("42% left", "41"), record, now + 900)

        assertTrue(decision.publishesGauge)
    }

    @Test
    fun `should not resend an unchanged widget gauge for the keep-alive`() {
        val standing = payload("42% left", "42")
        val record = NotifyPublishRecord(standing, tileAtSeconds = now, gaugeAtSeconds = now)

        val decision = gate.decide(standing, record, now + 5400)

        assertFalse(decision.publishesGauge)
    }

    // The Home Screen tile

    @Test
    fun `should never send a Home Screen tile the person turned off`() {
        val decision = gate.decide(payload("42% left", "42", screenTile = null), since = null, nowSeconds = now)

        assertFalse(decision.publishesScreenTile)
        assertTrue(decision.publishesTile)
    }

    @Test
    fun `should hold back a changed Home Screen tile until fifteen minutes have passed`() {
        val standing = payload("42% left", "42", "42% left")
        val record = NotifyPublishRecord(standing, tileAtSeconds = now, gaugeAtSeconds = now, screenTileAtSeconds = now)

        val decision = gate.decide(payload("41% left", "42", "41% left"), record, now + 300)

        // The phone polls on iOS's quarter hour: a write five minutes in is read by nobody.
        assertFalse(decision.publishesScreenTile)
    }

    @Test
    fun `should send a changed Home Screen tile once fifteen minutes have passed`() {
        val standing = payload("42% left", "42", "42% left")
        val record = NotifyPublishRecord(standing, tileAtSeconds = now, gaugeAtSeconds = now, screenTileAtSeconds = now)

        val decision = gate.decide(payload("41% left", "42", "41% left"), record, now + 900)

        assertTrue(decision.publishesScreenTile)
    }

    @Test
    fun `should resend an unchanged Home Screen tile after ninety minutes so it does not go stale`() {
        // Two hours after the last write the phone dims the tile as stale.
        val standing = payload("42% left", "42", "42% left")
        val record = NotifyPublishRecord(standing, tileAtSeconds = now, gaugeAtSeconds = now, screenTileAtSeconds = now)

        val decision = gate.decide(standing, record, now + 5400)

        assertTrue(decision.publishesScreenTile)
    }

    @Test
    fun `should remember the Live Activity tile and widget gauge as still showing their old values when only the Home Screen tile was sent`() {
        val first = payload("42% left", "42", "42% left")
        val second = payload("41% left", "41", "41% left")
        val record = NotifyPublishRecord(first, tileAtSeconds = now, gaugeAtSeconds = now, screenTileAtSeconds = now)

        val updated = record.updated(
            second,
            NotifyPublishDecision(publishesTile = false, publishesGauge = false, publishesScreenTile = true),
            now + 900,
        )

        assertEquals(second.screenTile, updated.payload.screenTile)
        assertEquals(now + 900, updated.screenTileAtSeconds)
        assertEquals(first.tile, updated.payload.tile)
        assertEquals(first.gauge, updated.payload.gauge)
        assertEquals(now, updated.tileAtSeconds)
        assertEquals(now, updated.gaugeAtSeconds)
    }

    @Test
    fun `should count sending only the Home Screen tile as sending something`() {
        assertFalse(NotifyPublishDecision(publishesTile = false, publishesGauge = false, publishesScreenTile = true).publishesNothing)
        assertFalse(NotifyPublishDecision.nothing.publishesScreenTile)
    }

    // Surfaces the person turned off

    @Test
    fun `should never send a Live Activity tile the person turned off`() {
        val decision = gate.decide(payload(null, "42"), since = null, nowSeconds = now)

        assertFalse(decision.publishesTile)
        assertTrue(decision.publishesGauge)
    }

    @Test
    fun `should never send a widget gauge the person turned off`() {
        val decision = gate.decide(payload("42% left", null), since = null, nowSeconds = now)

        assertFalse(decision.publishesGauge)
        assertTrue(decision.publishesTile)
    }

    // The record

    @Test
    fun `should remember the widget gauge as still showing its old value when only the tile was sent`() {
        val record = NotifyPublishRecord(payload("42% left", "42"), tileAtSeconds = now, gaugeAtSeconds = now)
        val next = payload("41% left", "41")

        val updated = record.updated(next, NotifyPublishDecision(publishesTile = true, publishesGauge = false), now + 120)

        assertEquals(next.tile, updated.payload.tile)
        assertEquals(record.payload.gauge, updated.payload.gauge)
        assertEquals(now + 120, updated.tileAtSeconds)
        assertEquals(now, updated.gaugeAtSeconds)
    }

    // The decision

    @Test
    fun `should count sending no surface as sending nothing`() {
        assertTrue(NotifyPublishDecision.nothing.publishesNothing)
        assertFalse(NotifyPublishDecision.nothing.publishesTile)
        assertFalse(NotifyPublishDecision.nothing.publishesGauge)
        assertEquals(NotifyPublishDecision.nothing, NotifyPublishDecision(publishesTile = false, publishesGauge = false))
    }

    @Test
    fun `should count sending one surface as sending something`() {
        assertFalse(NotifyPublishDecision(publishesTile = true, publishesGauge = false).publishesNothing)
        assertFalse(NotifyPublishDecision(publishesTile = false, publishesGauge = true).publishesNothing)
    }

    // What each surface is actually showing

    @Test
    fun `should still send a widget gauge change held back while the tile went out, once fifteen minutes have passed`() {
        val first = payload(tileTrailing = "2:14", gaugeValue = "42")
        val second = payload(tileTrailing = "2:13", gaugeValue = "41")

        var record = NotifyPublishRecord(NotifyPayload.empty)
            .updated(first, NotifyPublishDecision(publishesTile = true, publishesGauge = true), now)

        val atOneMinute = now + 60
        val tileOnly = gate.decide(second, record, atOneMinute)
        assertTrue(tileOnly.publishesTile)
        assertFalse(tileOnly.publishesGauge)
        record = record.updated(second, tileOnly, atOneMinute)

        // Recording the whole payload on the tile-only publish would have filed the new gauge as delivered.
        val later = gate.decide(second, record, now + 900)

        assertTrue(later.publishesGauge)
    }

    @Test
    fun `should remember a surface that was not sent as still showing its old value`() {
        val first = payload(tileTrailing = "2:14", gaugeValue = "42")
        val second = payload(tileTrailing = "2:13", gaugeValue = "41")

        val record = NotifyPublishRecord(first, tileAtSeconds = now, gaugeAtSeconds = now)
            .updated(second, NotifyPublishDecision(publishesTile = true, publishesGauge = false), now + 60)

        assertEquals(second.tile, record.payload.tile)
        assertEquals(first.gauge, record.payload.gauge)
    }
}
