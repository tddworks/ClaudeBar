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
        assertTrue(codex.accounts.all { it.isEnabled })
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
}
