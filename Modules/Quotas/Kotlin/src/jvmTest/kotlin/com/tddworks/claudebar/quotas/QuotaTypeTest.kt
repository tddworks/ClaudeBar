package com.tddworks.claudebar.quotas

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class QuotaTypeTest {
    @Test
    fun `should read back every quota from the key it was saved under`() {
        listOf(QuotaType.Session, QuotaType.Weekly, QuotaType.ModelSpecific("opus"), QuotaType.TimeLimit("Monthly"))
            .forEach { assertEquals(it, QuotaType.fromQuotaKey(it.quotaKey)) }
    }

    @Test
    fun `should keep the keys earlier versions saved`() {
        assertEquals("model:opus", QuotaType.ModelSpecific("opus").quotaKey)
        assertEquals("time:MCP Usage", QuotaType.TimeLimit("MCP Usage").quotaKey)
    }

    @Test
    fun `should read nothing from a key with an empty name or an unknown prefix`() {
        assertNull(QuotaType.fromQuotaKey("model:"))
        assertNull(QuotaType.fromQuotaKey("daily"))
    }

    @Test
    fun `should capitalize each word of a model's name`() {
        assertEquals("Claude-Opus 4", QuotaType.ModelSpecific("claude-OPUS 4").displayName)
    }

    @Test
    fun `should label session and weekly windows compactly for the menu bar`() {
        assertEquals("5h", QuotaType.Session.shortLabel)
        assertEquals("7d", QuotaType.Weekly.shortLabel)
    }

    @Test
    fun `should expect a monthly limit to refill in 30 days`() {
        assertEquals(QuotaDuration.Days(30), QuotaType.TimeLimit("monthly").conventionalWindow)
        assertEquals("30 days", QuotaDuration.Days(30).toString())
        assertEquals("1 hour", QuotaDuration.Hours(1).toString())
    }
}
