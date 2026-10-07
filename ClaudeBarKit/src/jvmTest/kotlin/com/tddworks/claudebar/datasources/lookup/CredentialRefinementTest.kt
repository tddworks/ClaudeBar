package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.Template
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * A key lookup that answers only when what it found matches (`match`), adds fixed values to it
 * (`with`), and reads a field from the first of several paths — and `{{url#host}}` in a template.
 * The data source turns "no key" into *sign in*; here that is the reader finding none.
 */
class CredentialRefinementTest {
    @TempDir
    lateinit var home: File

    private fun reader(lookup: CredentialLookup, environment: Map<String, String> = emptyMap()) =
        CredentialFinders(
            providerId = "acme", home = home.path, environment = { environment[it] },
            security = FakeSecurity { SecurityResult(1, "") }, secrets = null,
            database = FakeDatabase { _, _ -> emptyList() },
            browserCookies = FakeCookies(), browserStorage = FakeStorage(),
        ).reader(lookup)

    private fun config(json: String) = File(home, "config.json").writeText(json)

    /** The URL the data source would ask. */
    private fun usageURL(credential: Credential?) = credential?.let { Template.fill("https://{{baseURL#host}}/usage", it) }

    private val acmeConfig = """
    {"jsonFile":{"path":"~/config.json","token":["$.env.TOKEN","$.providers.0.key"],"baseURL":["$.env.BASE_URL","$.providers.0.base_url"]},
     "match":{"baseURL":"(api\\.acme\\.test|cn\\.acme\\.test)"}}
    """

    @Test
    fun `should find the key and its host in the next place the config holds them when the first is empty`() {
        config("""{"providers":[{"key":"k-1","base_url":"https://cn.acme.test/v1"}]}""")

        val found = reader(lookup(acmeConfig)).find()

        assertEquals("k-1", found?.credential?.token)
        assertEquals("https://cn.acme.test/usage", usageURL(found?.credential))
    }

    @Test
    fun `should ask to sign in, never sending the key elsewhere, when the found host isn't the provider's`() {
        config("""{"env":{"TOKEN":"k-1","BASE_URL":"https://api.anthropic.com"}}""")

        assertNull(reader(lookup(acmeConfig)).find())
    }

    @Test
    fun `should ask to sign in when a host filled from a blank setting doesn't fit the provider's`() {
        config("{}")
        val filled = lookup("""{"environment":"ACME_KEY","with":{"baseURL":"https://api.acme.test"},"match":{"baseURL":"acme\\.test"}}""")
        val blank = lookup("""{"environment":"ACME_KEY","with":{"baseURL":"https://{{setting.host}}"},"match":{"baseURL":"acme\\.test"}}""")

        assertNotNull(reader(filled, mapOf("ACME_KEY" to "k")).find())
        assertNull(reader(blank, mapOf("ACME_KEY" to "k")).find())
    }

    @Test
    fun `should add the definition's fixed values to the key it found, never replacing the key`() {
        val refined = lookup("""{"environment":"ACME_KEY","with":{"baseURL":"https://api.acme.test/v1","token":"not-this"}}""")
        assertEquals(listOf("${'$'}ACME_KEY"), refined.lookupOrder)

        val credential = reader(refined, mapOf("ACME_KEY" to "k-2")).find()?.credential

        assertEquals("https://api.acme.test/usage", usageURL(credential))
        assertEquals("Bearer k-2", Template.fill("Bearer {{token}}", credential))
    }

    @Test
    fun `should send each named cookie on its own, as well as the whole Cookie header`() {
        val refined = lookup("""{"environment":"ACME_COOKIE","cookies":["sec_token","csrf"]}""")

        val credential = reader(refined, mapOf("ACME_COOKIE" to "a=1; sec_token=s-9; csrf=c=2")).find()?.credential

        assertEquals("https://acme.test/usage?t=s-9", Template.fill("https://acme.test/usage?t={{sec_token}}", credential))
        assertEquals("c=2", Template.fill("{{csrf}}", credential))
        assertEquals("a=1; sec_token=s-9; csrf=c=2", Template.fill("{{token}}", credential))
    }

    @Test
    fun `should know no value for a named cookie the Cookie header lacks`() {
        val refinement = Refinement(cookies = listOf("sec_token"))
        assertTrue(refinement.cookieValues("a=1; b=2").isEmpty())
        assertEquals(
            CredentialLookup.Refined(CredentialLookup.Setting("cookie"), refinement),
            lookup("""{"setting":"cookie","cookies":["sec_token"]}"""),
        )
    }

    @Test
    fun `should keep the host rule when the definition is written out and read back`() {
        val refined = lookup(acmeConfig)
        assertEquals(refined, CredentialLookup.from(refined.toJson()))
    }
}
