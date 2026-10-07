package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.providers.TestDefinitions
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Feature: Updates
 *
 * Users manage app updates and beta channel preferences.
 *
 * Behaviors covered:
 * - #52–#54: when something fails, users can check the provider's status page
 *
 * Checking for updates (#52), the beta channel (#53) and the manual check (#54) are Sparkle and
 * AppSettings in the App, and stay in Swift.
 */
class UpdatesSpec {
    // Scenario: Update infrastructure

    @Test
    fun `should link Claude and Codex to their status pages`() {
        assertEquals("https://status.anthropic.com", TestDefinitions.builtIn("claude").profile.links.status)
        assertEquals("https://status.openai.com", TestDefinitions.builtIn("codex").profile.links.status)
    }
}
