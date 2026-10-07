package com.tddworks.claudebar.providers

import com.tddworks.claudebar.storage.SettingsFile
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** A provider's settings in settings.json, under the keys the app has always written. */
class JSONSettingsRepositoryProviderTest {
    private val file = temporarySettingsFile()
    private val repo = JsonProviderSettings(file, MemoryLegacyStore())

    private fun reopened() = JsonProviderSettings(SettingsFile(file.path), MemoryLegacyStore())

    // Provider Enabled State

    @Test
    fun `should show a provider when the person never turned it off`() {
        assertEquals(true, repo.isEnabled("claude"))
    }

    @Test
    fun `should hide a provider that starts off when the person never turned it on`() {
        assertEquals(false, repo.isEnabled("copilot", defaultValue = false))
    }

    @Test
    fun `should remember a provider turned off`() {
        repo.setEnabled(false, "claude")
        assertEquals(false, repo.isEnabled("claude"))
    }

    @Test
    fun `should keep each provider on or off independently`() {
        repo.setEnabled(false, "claude")
        repo.setEnabled(true, "codex")

        assertEquals(false, repo.isEnabled("claude"))
        assertEquals(true, repo.isEnabled("codex"))
    }

    // Custom Card URL

    @Test
    fun `should open no custom page from a card until one is set`() {
        assertNull(repo.customCardURL("claude"))
    }

    @Test
    fun `should remember a card's custom page`() {
        repo.setCustomCardURL("https://claude.owo.nz/", "claude")
        assertEquals("https://claude.owo.nz/", repo.customCardURL("claude"))
    }

    @Test
    fun `should forget a card's custom page when it is cleared`() {
        repo.setCustomCardURL("https://claude.owo.nz/", "claude")
        repo.setCustomCardURL(null, "claude")
        assertNull(repo.customCardURL("claude"))
    }

    @Test
    fun `should forget a card's custom page when it is set to nothing`() {
        repo.setCustomCardURL("https://claude.owo.nz/", "claude")
        repo.setCustomCardURL("", "claude")
        assertNull(repo.customCardURL("claude"))
    }

    @Test
    fun `should keep each provider's custom page apart`() {
        repo.setCustomCardURL("https://claude.owo.nz/", "claude")
        repo.setCustomCardURL("https://codex.example.com/", "codex")

        assertEquals("https://claude.owo.nz/", repo.customCardURL("claude"))
        assertEquals("https://codex.example.com/", repo.customCardURL("codex"))
        assertNull(repo.customCardURL("gemini"))
    }

    // Provider Order

    @Test
    fun `should keep no provider order until the person arranges them`() {
        assertEquals(emptyList<String>(), repo.providerOrder())
    }

    @Test
    fun `should remember the provider order across restarts`() {
        repo.setProviderOrder(listOf("gemini", "claude", "codex"))

        // A fresh repository over the same file, so the value really hit settings.json.
        assertEquals(listOf("gemini", "claude", "codex"), reopened().providerOrder())
    }

    @Test
    fun `should forget the provider order when it is cleared`() {
        repo.setProviderOrder(listOf("gemini", "claude", "codex"))
        repo.setProviderOrder(emptyList())
        assertEquals(emptyList<String>(), repo.providerOrder())
        assertNull(file.read("providers.order"))
    }

    @Test
    fun `should remember an order that names only some providers`() {
        repo.setProviderOrder(listOf("codex"))
        assertEquals(listOf("codex"), repo.providerOrder())
    }

    // Hidden Quota Keys (issue #140)

    @Test
    fun `should hide no quotas until the person hides some (#140)`() {
        assertEquals(emptySet<String>(), repo.hiddenQuotaKeys("gemini"))
    }

    @Test
    fun `should remember hidden quotas across restarts (#140)`() {
        repo.setHiddenQuotaKeys(setOf("time:mcp", "model:gemini-2.0-flash"), "gemini")

        assertEquals(setOf("model:gemini-2.0-flash", "time:mcp"), reopened().hiddenQuotaKeys("gemini"))
        assertEquals("""["model:gemini-2.0-flash","time:mcp"]""", file.read("providers.gemini.hiddenQuotaKeys").toString())
    }

    @Test
    fun `should keep each provider's hidden quotas apart (#140)`() {
        repo.setHiddenQuotaKeys(setOf("model:gemini-2.0-flash"), "gemini")
        repo.setHiddenQuotaKeys(setOf("weekly"), "codex")

        assertEquals(setOf("model:gemini-2.0-flash"), repo.hiddenQuotaKeys("gemini"))
        assertEquals(setOf("weekly"), repo.hiddenQuotaKeys("codex"))
        assertEquals(emptySet<String>(), repo.hiddenQuotaKeys("claude"))
    }

    @Test
    fun `should show every quota again once nothing is hidden (#140)`() {
        repo.setHiddenQuotaKeys(setOf("model:gemini-2.0-flash"), "gemini")
        repo.setHiddenQuotaKeys(emptySet(), "gemini")

        assertEquals(emptySet<String>(), repo.hiddenQuotaKeys("gemini"))
        assertNull(file.read("providers.gemini.hiddenQuotaKeys"))
    }

    // A provider's data source and its on/off settings — the keys the old cards wrote.
    // With nothing saved the generic repository answers null: the definition's default applies.

    @Test
    fun `should read Claude through its CLI when the person never chose`() {
        assertNull(repo.dataSourceKind("claude"))
    }

    @Test
    fun `should remember reading Claude through the API`() {
        repo.setDataSourceKind("api", "claude")
        assertEquals("api", repo.dataSourceKind("claude"))
        assertEquals("api", file.string("claude.probeMode"))
    }

    @Test
    fun `should fall back to Claude's CLI when the person never chose`() {
        assertNull(repo.isOn("cliFallbackEnabled", "claude"))
    }

    @Test
    fun `should remember turning Claude's CLI fallback off`() {
        repo.setOn(false, "cliFallbackEnabled", "claude")
        assertEquals(false, repo.isOn("cliFallbackEnabled", "claude"))
        assertEquals("false", file.read("claude.cliFallbackEnabled").toString())
    }

    @Test
    fun `should read Codex over RPC when the person never chose`() {
        assertNull(repo.dataSourceKind("codex"))
    }

    @Test
    fun `should remember reading Codex through the API`() {
        repo.setDataSourceKind("api", "codex")
        assertEquals("api", repo.dataSourceKind("codex"))
        assertEquals("api", file.string("codex.probeMode"))
    }

    @Test
    fun `should not count Codex as verified before it ever answered`() {
        assertNull(repo.isOn("verifiedAtLeastOnce", "codex"))
    }

    @Test
    fun `should remember whether Codex has been verified`() {
        repo.setOn(true, "verifiedAtLeastOnce", "codex")
        assertEquals(true, repo.isOn("verifiedAtLeastOnce", "codex"))

        repo.setOn(false, "verifiedAtLeastOnce", "codex")
        assertEquals(false, repo.isOn("verifiedAtLeastOnce", "codex"))
    }

    // The Swift suite's Hook Settings tests are not ported here: session hooks are a destination,
    // and their settings belong to the activity package's HookSettingsRepository.
}
