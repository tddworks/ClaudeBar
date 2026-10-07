package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.storage.SettingsFile
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** The person's quota-alert percentages, kept in settings.json. */
class QuotaAlertSettingsTest {
    @TempDir
    lateinit var dir: File

    private val path get() = File(dir, "settings.json").path

    @Test
    fun `should have no quota alert percentages until the person adds one`() {
        assertTrue(QuotaAlertSettings(SettingsFile(path)).quotaAlertPercents().isEmpty())
    }

    @Test
    fun `should remember quota alert percentages across restarts`() {
        QuotaAlertSettings(SettingsFile(path)).setQuotaAlertPercents(listOf(60, 35))

        val relaunched = QuotaAlertSettings(SettingsFile(path))

        assertEquals(listOf(60, 35), relaunched.quotaAlertPercents())
    }
}
