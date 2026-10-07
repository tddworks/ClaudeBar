package com.tddworks.claudebar.alerting

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NotifyDeviceLinkTest {

    // Pasted URLs

    @Test
    fun `should read the device id and token from a pasted notification link`() {
        val link = NotifyDeviceLink.fromPastedText("https://push.getnotifyapp.com/notify/ABCD1234?token=s3cr3t-t0k3n")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t-t0k3n", link?.token)
    }

    @Test
    fun `should read the device id and token from a pasted Live Activity link`() {
        val link = NotifyDeviceLink.fromPastedText("https://push.getnotifyapp.com/live-activity/ABCD1234?token=s3cr3t")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    @Test
    fun `should read the device id and token from a pasted widgets link`() {
        val link = NotifyDeviceLink.fromPastedText("https://push.getnotifyapp.com/widgets/ABCD1234?token=s3cr3t")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    @Test
    fun `should refuse a pasted link that has no token`() {
        // The gateway will not talk without the secret: better refused in the pane than found as a 403.
        assertNull(NotifyDeviceLink.fromPastedText("https://push.getnotifyapp.com/notify/ABCD1234"))
    }

    // Pasted pairs

    @Test
    fun `should read an id and token pasted with a space between them`() {
        val link = NotifyDeviceLink.fromPastedText("ABCD1234 s3cr3t")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    @Test
    fun `should read an id and token pasted with a comma between them`() {
        val link = NotifyDeviceLink.fromPastedText("ABCD1234,s3cr3t")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    @Test
    fun `should read an id and token pasted with a colon between them`() {
        val link = NotifyDeviceLink.fromPastedText("ABCD1234:s3cr3t")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    // Rejected input

    @Test
    fun `should refuse a pasted id shorter than eight characters`() {
        assertNull(NotifyDeviceLink.fromPastedText("ABC1234 s3cr3t"))
    }

    @Test
    fun `should refuse a pasted id longer than thirty-two characters`() {
        assertNull(NotifyDeviceLink.fromPastedText("A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q s3cr3t"))
    }

    @Test
    fun `should refuse a pasted id with characters other than letters and digits`() {
        assertNull(NotifyDeviceLink.fromPastedText("ABCD_1234 s3cr3t"))
    }

    @Test
    fun `should refuse an empty or blank paste`() {
        assertNull(NotifyDeviceLink.fromPastedText(""))
        assertNull(NotifyDeviceLink.fromPastedText("   \n "))
    }

    // Trimming

    @Test
    fun `should ignore spaces and newlines around a pasted link`() {
        val link = NotifyDeviceLink.fromPastedText("  https://push.getnotifyapp.com/notify/ABCD1234?token=s3cr3t\n")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    @Test
    fun `should ignore spaces around a typed id and token`() {
        val link = NotifyDeviceLink.of("  ABCD1234  ", "  s3cr3t  ")

        assertEquals("ABCD1234", link?.deviceId)
        assertEquals("s3cr3t", link?.token)
    }

    // Device id shape

    @Test
    fun `should accept the id lengths Notify! issues, from eight to thirty-two characters`() {
        assertTrue(NotifyDeviceLink.isValidDeviceId("ABCD1234"))
        assertTrue(NotifyDeviceLink.isValidDeviceId("WBabcdef12345678"))
        assertTrue(NotifyDeviceLink.isValidDeviceId("A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6"))
    }

    @Test
    fun `should refuse an id outside eight to thirty-two characters`() {
        assertFalse(NotifyDeviceLink.isValidDeviceId("ABC1234"))
        assertFalse(NotifyDeviceLink.isValidDeviceId("A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q"))
    }

    // Half a link

    @Test
    fun `should find the device id in a pasted link that has no token`() {
        // The gateway's own /link answer hands back a URL with the token stripped.
        assertEquals("ABC12345", NotifyDeviceLink.deviceIdInPastedText("https://push.getnotifyapp.com/notify/ABC12345"))
    }

    @Test
    fun `should find the device id when the person pastes the id alone`() {
        assertEquals("ABC12345", NotifyDeviceLink.deviceIdInPastedText("  ABC12345  "))
    }

    @Test
    fun `should find just the device id in a pasted id and token`() {
        assertEquals("ABC12345", NotifyDeviceLink.deviceIdInPastedText("ABC12345 sekret-token"))
    }

    @Test
    fun `should find no device id in text that names none`() {
        assertNull(NotifyDeviceLink.deviceIdInPastedText(""))
        assertNull(NotifyDeviceLink.deviceIdInPastedText("not a link"))
        assertNull(NotifyDeviceLink.deviceIdInPastedText("https://push.getnotifyapp.com/notify/short"))
    }

    // Device kind

    @Test
    fun `should know a GRP id with five more characters as a group`() {
        // Eight characters, a legacy id's length: the prefix tells them apart, as the gateway's router does.
        assertEquals(NotifyDeviceKind.GROUP, NotifyDeviceKind.of("GRPA1B2C"))
    }

    @Test
    fun `should know a WB id with fourteen more characters as a browser`() {
        assertEquals(NotifyDeviceKind.WEB, NotifyDeviceKind.of("WB9K4TR2ZQ7M1XPD"))
    }

    @Test
    fun `should know an MC id with fourteen more characters as a Mac`() {
        assertEquals(NotifyDeviceKind.MAC, NotifyDeviceKind.of("MC3F7Q2ZKM4H2QZ1"))
    }

    @Test
    fun `should know an IO id with fourteen more characters as an app device with both Lock Screen surfaces`() {
        assertEquals(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.of("IO7Q2ZKM4H2QZ1XY"))
        assertTrue(NotifyDeviceKind.of("IO7Q2ZKM4H2QZ1XY").supportsLiveActivity)
        assertTrue(NotifyDeviceKind.of("IO7Q2ZKM4H2QZ1XY").supportsWidget)
    }

    @Test
    fun `should offer both Lock Screen surfaces, unexplained, to an app device id of a length nobody has seen yet`() {
        // The rule is which namespaces cannot, never which lengths may.
        val kind = NotifyDeviceKind.of("A1B2C3D4E5F6")

        assertTrue(kind.supportsLiveActivity)
        assertTrue(kind.supportsWidget)
        assertNull(kind.liveActivityUnsupportedReason)
        assertNull(kind.widgetUnsupportedReason)
    }

    @Test
    fun `should know a bare eight-character id as an app device`() {
        assertEquals(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.of("ABCD1234"))
    }

    @Test
    fun `should know a lowercase or mixed-case eight-character id as an app device`() {
        // Older Mac listeners minted the legacy format in mixed case.
        assertEquals(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.of("abcd1234"))
        assertEquals(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.of("AbCd1234"))
    }

    @Test
    fun `should not know an id whose prefix is followed by the wrong number of characters`() {
        assertEquals(NotifyDeviceKind.UNRECOGNIZED, NotifyDeviceKind.of("WB9K4TR2ZQ7M1XP"))
        assertEquals(NotifyDeviceKind.UNRECOGNIZED, NotifyDeviceKind.of("GRPA1B2C3"))
    }

    @Test
    fun `should know an eight-character id starting with WB as an ordinary app device`() {
        assertEquals(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.of("WBA1B2C3"))
    }

    @Test
    fun `should not read a prefix as its namespace when lowercase characters follow it`() {
        assertEquals(NotifyDeviceKind.UNRECOGNIZED, NotifyDeviceKind.of("WBabcdef12345678"))
        assertEquals(NotifyDeviceKind.UNRECOGNIZED, NotifyDeviceKind.of("MCabcdef12345678"))
        assertEquals(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.of("GRPabcde"))
    }

    @Test
    fun `should let a Mac or a browser keep a widget but not show a Live Activity`() {
        for (kind in listOf(NotifyDeviceKind.MAC, NotifyDeviceKind.WEB)) {
            assertFalse(kind.supportsLiveActivity)
            assertTrue(kind.supportsWidget)
            assertTrue(kind.supportsAnySurface)
        }
    }

    @Test
    fun `should offer a group neither a Live Activity nor a widget`() {
        assertFalse(NotifyDeviceKind.GROUP.supportsLiveActivity)
        assertFalse(NotifyDeviceKind.GROUP.supportsWidget)
        assertFalse(NotifyDeviceKind.GROUP.supportsAnySurface)
    }

    @Test
    fun `should offer an app device both a Live Activity and a widget`() {
        assertTrue(NotifyDeviceKind.APP_DEVICE.supportsLiveActivity)
        assertTrue(NotifyDeviceKind.APP_DEVICE.supportsWidget)
        assertTrue(NotifyDeviceKind.APP_DEVICE.supportsAnySurface)
    }

    @Test
    fun `should let an app device, a Mac, a browser or an unknown device keep a Home Screen widget`() {
        for (kind in listOf(NotifyDeviceKind.APP_DEVICE, NotifyDeviceKind.MAC, NotifyDeviceKind.WEB, NotifyDeviceKind.UNRECOGNIZED)) {
            assertTrue(kind.supportsScreenWidget)
            assertNull(kind.screenWidgetUnsupportedReason)
        }
    }

    @Test
    fun `should not let a group keep a Home Screen widget, and say why`() {
        assertFalse(NotifyDeviceKind.GROUP.supportsScreenWidget)
        assertNotNull(NotifyDeviceKind.GROUP.screenWidgetUnsupportedReason)
    }

    @Test
    fun `should let an id from an unknown namespace through to both surfaces`() {
        val kind = NotifyDeviceKind.of("XY9K4TR2ZQ7M1XPD")

        assertEquals(NotifyDeviceKind.UNRECOGNIZED, kind)
        assertTrue(kind.supportsLiveActivity)
        assertTrue(kind.supportsWidget)
    }

    @Test
    fun `should explain a surface exactly when it is unavailable`() {
        for (kind in NotifyDeviceKind.entries) {
            assertEquals(kind.supportsLiveActivity, kind.liveActivityUnsupportedReason == null)
            assertEquals(kind.supportsWidget, kind.widgetUnsupportedReason == null)
        }
    }

    @Test
    fun `should tell a Mac person that the iPhone shows Live Activities and the widget still works`() {
        val reason = NotifyDeviceKind.MAC.liveActivityUnsupportedReason

        assertEquals(true, reason?.contains("iPhone"))
        assertEquals(true, reason?.contains("widget"))
    }

    @Test
    fun `should accept a pasted group link as a group with no Lock Screen surfaces`() {
        val link = NotifyDeviceLink.fromPastedText("https://push.getnotifyapp.com/notify/GRPA1B2C?token=s3cr3t")

        assertEquals("GRPA1B2C", link?.deviceId)
        assertEquals(NotifyDeviceKind.GROUP, link?.kind)
        assertEquals(false, link?.supportsLiveActivity)
        assertEquals(false, link?.supportsWidget)
    }

    @Test
    fun `should offer a Mac link a widget but not a Live Activity`() {
        val link = NotifyDeviceLink.of("MC3F7Q2ZKM4H2QZ1", "s3cr3t")

        assertEquals(NotifyDeviceKind.MAC, link?.kind)
        assertEquals(false, link?.supportsLiveActivity)
        assertEquals(true, link?.supportsWidget)
    }

    // Device description

    @Test
    fun `should describe a device as its name with its platform in parentheses`() {
        assertEquals("Apollo (iOS)", NotifyDeviceInfo("ABCD1234", "Apollo", "iOS").displayDescription)
    }

    @Test
    fun `should describe a device by its name alone when it has no platform`() {
        assertEquals("Apollo", NotifyDeviceInfo("ABCD1234", "Apollo").displayDescription)
        assertEquals("Apollo", NotifyDeviceInfo("ABCD1234", "Apollo", "").displayDescription)
    }
}
