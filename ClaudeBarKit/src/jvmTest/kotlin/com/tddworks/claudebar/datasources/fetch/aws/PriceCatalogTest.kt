package com.tddworks.claudebar.datasources.fetch.aws

import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** The price list as a PriceCatalog: exact per-million prices, the model's name and vendor, and the bundled table when the API can't answer. */
class PriceCatalogTest {
    internal class Prices(private val models: Map<String, PricedModel>) : ModelPricing {
        override suspend fun model(id: String) = models[id] ?: throw PricingError("No pricing found for $id")
    }

    @Test
    fun `should give exact price texts per million tokens, and none for an unknown model`() = runTest {
        val catalog = AWSPriceCatalog(
            Prices(mapOf("anthropic.claude-sonnet-4" to PricedModel("anthropic.claude-sonnet-4", "Claude Sonnet 4", "Anthropic", DecimalText.normalized("3.00")!!, "15"))),
        )

        val prices = catalog.prices("AmazonBedrock", listOf("anthropic.claude-sonnet-4", "acme.unknown"))

        assertEquals(
            mapOf("input" to "3", "output" to "15", "per" to "1000000", "name" to "Claude Sonnet 4", "vendor" to "Anthropic"),
            prices["anthropic.claude-sonnet-4"],
        )
        assertNull(prices["acme.unknown"])
    }

    @Test
    fun `should have no prices for a service other than Bedrock`() = runTest {
        assertTrue(AWSPriceCatalog(Prices(emptyMap())).prices("AmazonEC2", listOf("x")).isEmpty())
    }

    @Test
    fun `should price a cross-region model like its base model in the bundled price table`() {
        val regional = BundledModelPrices.model("us.anthropic.claude-opus-4-5-20251101-v1:0")!!
        val base = BundledModelPrices.model("anthropic.claude-opus-4-5-20251101-v1:0")!!

        assertEquals(base.inputPerMillion, regional.inputPerMillion)
        assertEquals(base.outputPerMillion, regional.outputPerMillion)
        assertNotEquals("0", regional.inputPerMillion)
    }
}

class ProfileResolutionTest {
    @TempDir
    lateinit var root: File

    @Test
    fun `should resolve a named static profile without requiring SSO`() {
        File(root, "config").writeText("")
        File(root, "credentials").writeText(
            "[default]\naws_access_key_id = fake-personal\naws_secret_access_key = fake-personal-secret\n" +
                "[work]\naws_access_key_id = fake-work\naws_secret_access_key = fake-work-secret\n",
        )
        val files = mapOf("AWS_CONFIG_FILE" to "${root.path}/config", "AWS_SHARED_CREDENTIALS_FILE" to "${root.path}/credentials")
        val resolver = AWSCredentialResolver(root.path) { files[it] }

        val identity = resolver.resolve("work")

        assertEquals("fake-work", identity.accessKeyId)
        assertEquals("fake-work-secret", identity.secretAccessKey)
        assertThrows<AWSCredentialsError> { resolver.resolve("missing") }
    }
}
