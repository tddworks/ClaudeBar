package com.tddworks.claudebar.alerting

import com.tddworks.claudebar.storage.CredentialRepository
import com.tddworks.claudebar.storage.SettingsFile
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** Notify!'s settings in settings.json, and its token in the vault. */
internal class NotifySettingsRepositoryTest {
    @TempDir
    lateinit var dir: File

    private val deviceId = "ABC12345"
    private val token = "sekret-token-42"

    /** A vault that keeps what it is given. */
    private class Kept : CredentialRepository {
        val values = mutableMapOf<String, String>()
        override fun save(value: String, key: String) {
            values[key] = value
        }
        override fun get(key: String) = values[key]
        override fun delete(key: String): Boolean {
            values.remove(key)
            return true
        }
    }

    /**
     * The Keychain as a locally built ClaudeBar meets it: ad-hoc signed, so every call comes
     * back errSecAuthFailed and keeps nothing, while looking like success to the caller.
     */
    private class Refusing : CredentialRepository {
        override fun save(value: String, key: String) = Unit
        override fun get(key: String): String? = null
        override fun delete(key: String) = true
    }

    private val settingsFile get() = File(dir, "settings.json")
    private val secure = Kept()
    private val fallback = Kept()

    private fun repository(secure: CredentialRepository = this.secure) =
        NotifySettings(SettingsFile(settingsFile.path), secure, fallback)

    private val repository by lazy { repository() }

    // Defaults

    @Test
    fun `should keep Notify! off until the person turns it on`() {
        // It sends quota data to a third party, so it can never start out on.
        assertEquals(NotifyConstants.DEFAULT_ENABLED, repository.isNotifyEnabled())
        assertFalse(repository.isNotifyEnabled())
    }

    @Test
    fun `should show the Lock Screen tile and the widget once Notify! is linked, unless turned off`() {
        assertTrue(repository.isNotifyLiveActivityEnabled())
        assertTrue(repository.isNotifyWidgetEnabled())
    }

    @Test
    fun `should show the Home Screen tile once Notify! is linked, unless turned off`() {
        assertEquals(NotifyConstants.DEFAULT_SCREEN_WIDGET_ENABLED, repository.isNotifyScreenWidgetEnabled())
        assertTrue(repository.isNotifyScreenWidgetEnabled())
    }

    @Test
    fun `should have no linked phone to begin with`() {
        assertEquals("", repository.notifyDeviceId())
    }

    @Test
    fun `should choose no gauge quota to begin with`() {
        // Empty spells "whichever quota needs attention most".
        assertEquals("", repository.notifyGaugeProviderId())
        assertEquals("", repository.notifyGaugeQuotaKey())
    }

    @Test
    fun `should know of no Lock Screen tile or widget to begin with`() {
        assertNull(repository.notifyActivityId())
        assertNull(repository.notifyWidgetId())
    }

    @Test
    fun `should have no Notify! token to begin with`() {
        assertNull(repository.notifyDeviceToken())
        assertFalse(repository.hasNotifyDeviceToken())
    }

    // Setters

    @Test
    fun `should remember Notify! turned on`() {
        repository.setNotifyEnabled(true)
        assertTrue(repository().isNotifyEnabled())
    }

    @Test
    fun `should remember the linked phone`() {
        repository.setNotifyDeviceId(deviceId)
        assertEquals(deviceId, repository().notifyDeviceId())
    }

    @Test
    fun `should remember the Lock Screen tile turned off`() {
        repository.setNotifyLiveActivityEnabled(false)
        assertFalse(repository().isNotifyLiveActivityEnabled())
    }

    @Test
    fun `should remember the widget turned off`() {
        repository.setNotifyWidgetEnabled(false)
        assertFalse(repository().isNotifyWidgetEnabled())
    }

    @Test
    fun `should remember the Home Screen tile turned off`() {
        repository.setNotifyScreenWidgetEnabled(false)
        assertFalse(repository().isNotifyScreenWidgetEnabled())
    }

    @Test
    fun `should remember the gauge's provider`() {
        repository.setNotifyGaugeProviderId("claude")
        assertEquals("claude", repository().notifyGaugeProviderId())
    }

    @Test
    fun `should remember the gauge's quota`() {
        repository.setNotifyGaugeQuotaKey("five-hour")
        assertEquals("five-hour", repository().notifyGaugeQuotaKey())
    }

    @Test
    fun `should remember the Lock Screen tile it started`() {
        repository.setNotifyActivityId("LA7Q2ZKM")
        assertEquals("LA7Q2ZKM", repository().notifyActivityId())
    }

    @Test
    fun `should remember the widget it created`() {
        repository.setNotifyWidgetId("WG4H2QZ1")
        assertEquals("WG4H2QZ1", repository().notifyWidgetId())
    }

    @Test
    fun `should remember the Home Screen tile it created`() {
        repository.setNotifyScreenWidgetId("SW8N3PQ2")
        assertEquals("SW8N3PQ2", repository().notifyScreenWidgetId())
    }

    // Forgetting a handle

    @Test
    fun `should forget the Lock Screen tile once it is cleared`() {
        repository.setNotifyActivityId("LA7Q2ZKM")
        repository.setNotifyActivityId(null)

        // Removed, not "": a stored "" would read back as a handle to a tile that no longer exists.
        assertNull(repository.notifyActivityId())
        assertFalse("activityId" in settingsFile.readText())
    }

    @Test
    fun `should forget the widget once it is cleared`() {
        repository.setNotifyWidgetId("WG4H2QZ1")
        repository.setNotifyWidgetId(null)

        assertNull(repository.notifyWidgetId())
    }

    @Test
    fun `should forget the Home Screen tile once it is cleared`() {
        repository.setNotifyScreenWidgetId("SW8N3PQ2")
        repository.setNotifyScreenWidgetId(null)

        assertNull(repository.notifyScreenWidgetId())
    }

    // Device token

    @Test
    fun `should keep the Notify! token in secure storage`() {
        repository.saveNotifyDeviceToken(token)

        assertEquals(token, repository.notifyDeviceToken())
        assertTrue(repository.hasNotifyDeviceToken())
        assertEquals(token, secure.get(NotifySettings.TOKEN_KEY))
    }

    @Test
    fun `should trim the spaces and newline a pasted token arrives with`() {
        repository.saveNotifyDeviceToken("  $token\n")

        assertEquals(token, repository.notifyDeviceToken())
    }

    @Test
    fun `should forget the Notify! token when it is removed`() {
        repository.saveNotifyDeviceToken(token)

        assertTrue(repository.deleteNotifyDeviceToken())
        assertNull(repository.notifyDeviceToken())
        assertFalse(repository.hasNotifyDeviceToken())
    }

    @Test
    fun `should unlink when the token is saved blank`() {
        repository.saveNotifyDeviceToken(token)
        repository.saveNotifyDeviceToken("")

        // An empty field is unlinking, not a blank secret that would look linked and then fail.
        assertNull(repository.notifyDeviceToken())
        assertFalse(repository.hasNotifyDeviceToken())
    }

    @Test
    fun `should unlink when the token is saved as only whitespace`() {
        repository.saveNotifyDeviceToken(token)
        repository.saveNotifyDeviceToken(" \n\t ")

        assertNull(repository.notifyDeviceToken())
        assertFalse(repository.hasNotifyDeviceToken())
    }

    @Test
    fun `should never write the Notify! token to settings json`() {
        repository.setNotifyDeviceId(deviceId)
        repository.saveNotifyDeviceToken(token)

        // The id being there proves this is the file the repository writes.
        val contents = settingsFile.readText()
        assertTrue(deviceId in contents)
        assertFalse(token in contents)
    }

    // Device link

    @Test
    fun `should have no link to the phone until a token is saved`() {
        repository.setNotifyDeviceId(deviceId)

        assertNull(repository.notifyDeviceLink())
    }

    @Test
    fun `should have no link to the phone when its id is malformed`() {
        repository.setNotifyDeviceId("ABC1")
        repository.saveNotifyDeviceToken(token)

        assertNull(repository.notifyDeviceLink())
    }

    @Test
    fun `should link the phone once both its id and token are saved`() {
        repository.setNotifyDeviceId(deviceId)
        repository.saveNotifyDeviceToken(token)

        val link = repository.notifyDeviceLink()
        assertNotNull(link)
        assertEquals(deviceId, link!!.deviceId)
        assertEquals(token, link.token)
    }

    // Gauge selection

    @Test
    fun `should pick the gauge quota automatically when no provider is chosen`() {
        repository.setNotifyGaugeQuotaKey("five-hour")

        assertTrue(repository.notifyGaugeSelection().isAutomatic)
    }

    @Test
    fun `should pick the gauge quota automatically when no quota is chosen`() {
        repository.setNotifyGaugeProviderId("claude")

        assertTrue(repository.notifyGaugeSelection().isAutomatic)
    }

    @Test
    fun `should show the chosen quota on the gauge when provider and quota are both chosen`() {
        repository.setNotifyGaugeProviderId("claude")
        repository.setNotifyGaugeQuotaKey("five-hour")

        val selection = repository.notifyGaugeSelection()
        assertFalse(selection.isAutomatic)
        assertEquals(NotifyGaugeSelection(providerId = "claude", quotaKey = "five-hour"), selection)
    }

    // When the Keychain refuses

    @Test
    fun `should still keep the Notify! token when the Keychain refuses it`() {
        val repository = repository(secure = Refusing())

        repository.saveNotifyDeviceToken(token)

        assertEquals(token, repository.notifyDeviceToken())
        assertTrue(repository.hasNotifyDeviceToken())
    }

    @Test
    fun `should say the Notify! token is not secure when the Keychain refuses it`() {
        val repository = repository(secure = Refusing())

        repository.saveNotifyDeviceToken(token)

        // The pane's badge must not read as "in the Keychain" when it is not.
        assertFalse(repository.notifyDeviceTokenIsSecure())
    }

    @Test
    fun `should never write the Notify! token to settings json when the Keychain refuses it`() {
        val repository = repository(secure = Refusing())

        repository.setNotifyDeviceId(deviceId)
        repository.saveNotifyDeviceToken(token)

        val contents = settingsFile.readText()
        assertFalse(token in contents)
        assertTrue(deviceId in contents)
    }

    @Test
    fun `should forget the Notify! token from the fallback store when the Keychain refused it`() {
        val repository = repository(secure = Refusing())
        repository.saveNotifyDeviceToken(token)

        repository.deleteNotifyDeviceToken()

        assertNull(repository.notifyDeviceToken())
        assertFalse(repository.hasNotifyDeviceToken())
    }

    // Saving a link

    @Test
    fun `should keep the tile and widgets already on the phone when the same phone is saved again`() {
        repository.saveNotifyDeviceLink(NotifyDeviceLink.of(deviceId, token)!!)
        repository.setNotifyActivityId("LA7Q2ZKM")
        repository.setNotifyWidgetId("WG4H2QZ1")
        repository.setNotifyScreenWidgetId("SW3K9QZ2")

        // Save pressed again, with a rotated token but the same phone.
        repository.saveNotifyDeviceLink(NotifyDeviceLink.of(deviceId, "a-rotated-token")!!)

        assertEquals("LA7Q2ZKM", repository.notifyActivityId())
        assertEquals("WG4H2QZ1", repository.notifyWidgetId())
        assertEquals("SW3K9QZ2", repository.notifyScreenWidgetId())
        assertEquals("a-rotated-token", repository.notifyDeviceToken())
    }

    @Test
    fun `should forget the previous phone's tile and widgets when a different phone is linked`() {
        repository.saveNotifyDeviceLink(NotifyDeviceLink.of(deviceId, token)!!)
        repository.setNotifyActivityId("LA7Q2ZKM")
        repository.setNotifyWidgetId("WG4H2QZ1")
        repository.setNotifyScreenWidgetId("SW3K9QZ2")

        repository.saveNotifyDeviceLink(NotifyDeviceLink.of("ZZZ99999", token)!!)

        assertNull(repository.notifyActivityId())
        assertNull(repository.notifyWidgetId())
        assertNull(repository.notifyScreenWidgetId())
        assertEquals("ZZZ99999", repository.notifyDeviceId())
    }
}
