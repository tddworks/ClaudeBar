package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.providers.CustomDefinitions
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.ProviderAccountConfig
import com.tddworks.claudebar.providers.ProviderCatalog
import com.tddworks.claudebar.providers.Providers
import com.tddworks.claudebar.providers.StubbedProvider
import com.tddworks.claudebar.providers.TestDefinitions
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Settings → Providers, by product (CANONICAL §1: the product's switch): one row per product,
 * its switch hiding every login, its logins moving together.
 */
class ProductTabsTest {
    private val stub = StubbedProvider("codex")
    private val folder = TestDefinitions.folder("product-tabs")

    @AfterEach
    fun cleanUp() {
        stub.cleanUp()
        folder.deleteRecursively()
    }

    /** Codex with two logins (*me* and *work*), then Claude with one. */
    private fun monitor(): Triple<QuotaMonitor, Provider, Provider> {
        val work = ProviderAccountConfig("work", "work", probeConfig = mapOf("codexHome" to "/tmp/work", "chatgptAccountId" to "work"))
        val codex = stub.makeProvider("codex", listOf(work))
        val claude = stub.makeProvider("claude")
        val catalog = ProviderCatalog(TestDefinitions.builtIns, File(folder, "providers").path, File(folder, "extensions").path)
        val providers = Providers(listOf(codex, claude), catalog, stub.settings, customs = CustomDefinitions(), make = { error("tests don't add providers") })
        return Triple(QuotaMonitor(providers, settingsRepository = stub.settings), codex, claude)
    }

    @Test
    fun `should list each provider once with all its logins, whether on or off`() {
        val (monitor, codex, _) = monitor()
        codex.accounts[1].isEnabled = false

        val tabs = monitor.productTabs

        assertEquals(listOf("codex", "claude"), tabs.map { it.id })
        assertEquals(2, tabs[0].accounts.size)
    }

    @Test
    fun `should hide every login of a provider the person turns off, keeping each login's own switch`() {
        val (monitor, codex, _) = monitor()

        monitor.setProductEnabled(monitor.productTabs[0], enabled = false)

        assertFalse(monitor.productTabs[0].isEnabled)
        assertTrue(monitor.lineup.none { it.id.startsWith("codex") })
        assertTrue(codex.accounts.all.all { it.isEnabled })
    }

    @Test
    fun `should select another provider when the person turns off the selected one`() {
        val (monitor, _, _) = monitor()
        monitor.selectedProviderId = "codex"

        monitor.setProductEnabled(monitor.productTabs[0], enabled = false)

        assertEquals("claude", monitor.selectedProviderId)
    }

    @Test
    fun `should move a provider's logins together when the person moves the provider`() {
        val (monitor, _, _) = monitor()

        monitor.providers.move("claude", -1)

        assertEquals(listOf("claude", "codex"), monitor.productTabs.map { it.id })
        assertEquals(listOf("claude"), monitor.logins.map { it.id }.take(1))
        assertEquals(listOf("codex", "codex.work"), monitor.logins.map { it.id }.takeLast(2))
    }

    @Test
    fun `should name each login only when the provider has several`() {
        val (monitor, codex, claude) = monitor()
        codex.accounts.rename(codex.defaultAccount, "personal")

        assertEquals("personal", monitor.productTabs[0].loginName(codex.defaultAccount))
        assertEquals("work", monitor.productTabs[0].loginName(codex.accounts[1]))
        assertNull(monitor.productTabs[1].loginName(claude.defaultAccount))
    }

    @Test
    fun `should show the plain login's settings on a provider's page`() {
        val (monitor, codex, _) = monitor()

        assertSame(codex.defaultAccount, monitor.productTabs[0].page)
    }

    // The popover's pills: a provider's logins share one tab, in the person's order, and ⌘1 is the first tab.

    /** Claude, then Codex with *work* and *side*. */
    private fun lineup(): Triple<QuotaMonitor, Provider, Provider> {
        fun login(id: String) = ProviderAccountConfig(id, id.replaceFirstChar { it.uppercase() }, "$id@example.com",
            probeConfig = mapOf("codexHome" to "/tmp/$id", "chatgptAccountId" to id))
        val claude = stub.makeProvider("claude")
        val codex = stub.makeProvider("codex", listOf(login("work"), login("side")))
        val catalog = ProviderCatalog(TestDefinitions.builtIns, File(folder, "providers").path, File(folder, "extensions").path)
        val providers = Providers(listOf(claude, codex), catalog, stub.settings, customs = CustomDefinitions(), make = { error("tests don't add providers") })
        return Triple(QuotaMonitor(providers, settingsRepository = stub.settings), claude, codex)
    }

    @Test
    fun `should show a provider's logins under one tab`() {
        val (monitor, _, codex) = lineup()

        val tabs = ProductTab.tabs(monitor.logins, monitor.providers)

        assertEquals(listOf("claude", "codex"), tabs.map { it.id })
        assertEquals(codex.accounts.all.map { it.id }, tabs[1].accounts.map { it.id })
        assertEquals("Codex", tabs[1].name)
    }

    @Test
    fun `should keep the person's order in a tab and leave out paused logins`() {
        val (monitor, _, codex) = lineup()
        codex.accounts.move(codex.accounts[2], 0)
        codex.accounts[1].isEnabled = false

        val tab = ProductTab.tabs(codex.accounts.all.filter { it.isEnabled }, monitor.providers).first()

        assertEquals(listOf("codex.side", "codex.work"), tab.accounts.map { it.id })
    }

    @Test
    fun `should hold every one of its provider's logins in a tab, and no other's`() {
        val (monitor, _, _) = lineup()

        val codex = ProductTab.tabs(monitor.logins, monitor.providers).last()

        assertTrue(codex.contains("codex.work"))
        assertTrue(codex.contains("codex"))
        assertFalse(codex.contains("claude"))
    }

    @Test
    fun `should select the second tab with ⌘2 and keep it selected for any of its logins`() {
        val (monitor, _, codex) = lineup()

        monitor.selectProvider(atPosition = 2)

        assertEquals("codex", monitor.selectedTab?.id)
        assertEquals(codex.accounts[0].id, monitor.selectedProviderId)
        monitor.selectedProviderId = "codex.side"
        assertEquals("codex", monitor.selectedTab?.id)
        assertEquals(codex.accounts.all.map { it.id }, monitor.selectedLogins.map { it.id })
    }

    @Test
    fun `should hide a quota for every account of a provider once it is hidden (#140)`() {
        stub.settings.setHiddenQuotaKeys(setOf("model:codex-spark"), "codex")
        val (monitor, _, codex) = lineup()

        assertEquals(setOf("model:codex-spark"), monitor.hiddenQuotaKeys(codex.accounts[0]))
        assertEquals(setOf("model:codex-spark"), monitor.hiddenQuotaKeys(codex.accounts[1]))
    }
}
