package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.monitoring.StubbedProducts
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test

/**
 * Feature: Themes
 *
 * Users select visual themes from Settings.
 *
 * Behaviors covered:
 * - #49: Each provider has a distinct identity for themed display
 *
 * Theme selection (#49), following macOS light/dark (#50) and the Christmas window (#51) live in
 * the App's ThemeRegistry and stay in Swift; only the providers' identity is the domain's.
 */
class ThemesSpec {
    private val products = StubbedProducts()

    @AfterEach
    fun cleanUp() = products.cleanUp()

    // Scenario: Provider identity for themed display

    @Test
    fun `should give Claude and Codex their own id and lineup name`() {
        val claude = products.product("claude")
        val codex = products.product("codex")

        assertEquals("claude", claude.defaultAccount.id)
        assertEquals("Claude", claude.lineupName(claude.defaultAccount))
        assertEquals("codex", codex.defaultAccount.id)
        assertEquals("Codex", codex.lineupName(codex.defaultAccount))
        assertNotEquals(claude.defaultAccount.id, codex.defaultAccount.id)
    }
}
