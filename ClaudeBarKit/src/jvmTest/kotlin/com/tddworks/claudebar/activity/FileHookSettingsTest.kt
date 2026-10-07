package com.tddworks.claudebar.activity

import com.tddworks.claudebar.storage.SettingsFile
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class FileHookSettingsTest {
    @TempDir
    lateinit var dir: File

    private fun settings() = FileHookSettings(SettingsFile(File(dir, "settings.json").path))

    @Test
    fun `should keep hooks off until the person turns them on`() {
        assertFalse(settings().isHookEnabled())
        settings().setHookEnabled(true)
        assertTrue(settings().isHookEnabled())
    }

    @Test
    fun `should listen on the default port until another is saved`() {
        assertEquals(19847, settings().hookPort())
        settings().setHookPort(20000)
        assertEquals(20000, settings().hookPort())
    }

    @Test
    fun `should fall back to the default port when the saved one is zero or less`() {
        settings().setHookPort(0)
        assertEquals(19847, settings().hookPort())
    }

    @Test
    fun `should read the keys earlier versions wrote`() {
        File(dir, "settings.json").writeText("""{"hook":{"enabled":true,"port":19999}}""")
        assertTrue(settings().isHookEnabled())
        assertEquals(19999, settings().hookPort())
    }
}
