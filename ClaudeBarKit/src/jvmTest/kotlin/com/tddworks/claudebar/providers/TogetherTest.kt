package com.tddworks.claudebar.providers

import com.tddworks.claudebar.quotas.QuotaType
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * `"together": true` — a definition's data sources answer together (an extension's sections):
 * every one runs, the usage is their union in the definition's order, a failed one is left out
 * of it and shows beside it as fetch health, and the refresh fails only when all do
 * (docs/features/extensions/design.md).
 */
class TogetherTest {
    private val stub = StubbedProvider()
    private val folder = File(stub.home, "together")

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    private fun write(name: String, json: String) {
        folder.mkdirs()
        File(folder, name).writeText(json)
    }

    private fun definition(together: Boolean = true) = ProviderDefinition.parse(
        """
        {"profile":{"id":"ext-acme","name":"Acme","links":{}},"together":$together,
         "dataSources":[
          {"kind":"quotas","fetch":{"file":{"path":"${folder.path}/quotas.json"}},"mapping":{"usage":{}}},
          {"kind":"cost","fetch":{"file":{"path":"${folder.path}/cost.json"}},"mapping":{"usage":{}}}],
         "defaultDataSource":"quotas"}
        """,
        ProviderProfile.Origin.EXTENSION,
    )

    private fun provider(together: Boolean = true) = stub.make(definition(together))

    @Test
    fun `should show what every data source reports, together`() {
        write("quotas.json", """{"quotas":[{"type":"weekly","percentRemaining":62}]}""")
        write("cost.json", """{"costUsage":{"totalCost":10.26,"apiDuration":0}}""")
        val acme = provider()

        val usage = acme.refreshPlain().usage()

        assertEquals(62.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(10_260_000_000, usage.costUsage?.totalCostNanos)
    }

    @Test
    fun `should show what the others report and the failure beside it when one data source fails`() {
        write("quotas.json", """{"quotas":[{"type":"weekly","percentRemaining":62}]}""")
        val acme = provider()

        val usage = acme.refreshPlain().usage()

        assertEquals(62.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
        assertNull(usage.costUsage)
        assertNotNull(acme.defaultAccount.snapshot?.quota(QuotaType.Weekly))
        assertNotNull(acme.defaultAccount.lastError)
    }

    @Test
    fun `should fail only when every data source fails`() {
        folder.mkdirs()
        val acme = provider()

        assertTrue(acme.refreshPlain() is RefreshOutcome.Failed)
        assertNotNull(acme.defaultAccount.lastError)
    }

    @Test
    fun `should show only the chosen data source's usage when they do not answer together`() {
        write("quotas.json", """{"quotas":[{"type":"weekly","percentRemaining":62}]}""")
        write("cost.json", """{"costUsage":{"totalCost":10.26,"apiDuration":0}}""")
        val acme = provider(together = false)

        val usage = acme.refreshPlain().usage()

        assertNotNull(usage.quota(QuotaType.Weekly))
        assertNull(usage.costUsage)
    }

    @Test
    fun `should keep answering together after the provider is saved and read back`() {
        val definition = provider().definition

        val again = ProviderDefinition.parse(definition.toJson().toString(), ProviderProfile.Origin.EXTENSION)

        assertTrue(again.together)
    }
}
