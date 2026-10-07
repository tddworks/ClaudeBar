package com.tddworks.claudebar.providers

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * WHO IT IS — a built-in provider's name, links and face come from its definition, with the
 * exact values the `switch id` tables used to hold.
 */
class ProviderProfileTest {
    private fun shades(light: Triple<Double, Double, Double>, dark: Triple<Double, Double, Double>) = ProviderLook.Shades(
        ProviderLook.RGB(light.first, light.second, light.third),
        ProviderLook.RGB(dark.first, dark.second, dark.third),
    )

    @Test
    fun `should show Claude with its name, status page, symbol, icon and colours`() {
        val profile = TestDefinitions.builtIn("claude").profile

        assertEquals("claude", profile.id)
        assertEquals("Claude", profile.name)
        assertEquals(ProviderProfile.Origin.BUILT_IN, profile.origin)
        assertEquals("brain.fill", profile.look.symbol)
        assertEquals("ClaudeIcon", profile.look.icon)
        assertEquals(shades(Triple(0.95, 0.48, 0.38), Triple(0.98, 0.55, 0.45)), profile.look.color)
        assertEquals(shades(Triple(0.92, 0.45, 0.72), Triple(0.85, 0.35, 0.65)), profile.look.gradientEnd)
        assertEquals("https://status.anthropic.com", profile.links.status)
    }

    @Test
    fun `should show Codex with its name, symbol, icon and colours`() {
        val profile = TestDefinitions.builtIn("codex").profile

        assertEquals("Codex", profile.name)
        assertEquals("chevron.left.forwardslash.chevron.right", profile.look.symbol)
        assertEquals("CodexIcon", profile.look.icon)
        assertEquals(shades(Triple(0.18, 0.72, 0.68), Triple(0.35, 0.85, 0.78)), profile.look.color)
        assertEquals(shades(Triple(0.12, 0.52, 0.72), Triple(0.25, 0.65, 0.85)), profile.look.gradientEnd)
    }

    @Test
    fun `should find a login's provider from the login's lineup id, and none for an unknown provider`() {
        assertEquals("codex", TestDefinitions.builtIns.forLineupId("codex.4f2a")?.id)
        assertEquals("claude", TestDefinitions.builtIns.forLineupId("claude")?.id)
        assertNull(TestDefinitions.builtIns.forLineupId("acme-not-built-in"))
    }

    @Test
    fun `should mark a provider as custom when its file is the person's own, whatever the file says`() {
        val data = TestDefinitions.builtIns.text("codex")

        assertEquals(ProviderProfile.Origin.CUSTOM, ProviderDefinition.parse(data, ProviderProfile.Origin.CUSTOM).profile.origin)
    }
}
