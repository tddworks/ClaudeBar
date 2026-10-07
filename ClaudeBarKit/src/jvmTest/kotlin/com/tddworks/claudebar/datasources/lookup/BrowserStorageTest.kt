package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.Template
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * `browserStorage` — a value a browser keeps for a site, read like a cookie (ENGINE_DESIGN §2.9):
 * every value from one browser profile, the first profile with a token, never logged.
 */
class BrowserStorageTest {
    private val storageLookup = """
    {"browserStorage":{"origin":"https://app.devin.ai","values":{
      "token":{"key":"*auth1_session","path":"$.token"},
      "organization":{"key":"last-internal-org-for-external-org-v1-*"}}}}
    """

    private fun reader(stores: List<Map<String, String>>, json: String = storageLookup): BrowserStorageReader {
        val query = (lookup(json) as CredentialLookup.BrowserStorage).query
        return BrowserStorageReader(query, FakeStorage(stores, origin = "https://app.devin.ai"))
    }

    @Test
    fun `should read the token out of its JSON and the organization beside it`() {
        val store = mapOf(
            "persist:auth1_session" to """{"token":"auth1_abc","expires":1}""",
            "last-internal-org-for-external-org-v1-acme" to "\"org_123\"",
            "unrelated" to "x",
        )

        val credential = requireNotNull(reader(listOf(store)).find()).credential

        assertEquals("auth1_abc", credential.token)
        assertEquals("org_123", credential["organization"])
    }

    @Test
    fun `should take every value from the first profile that has a token, never mixing profiles`() {
        val noToken = mapOf("last-internal-org-for-external-org-v1-other" to "\"org_other\"")
        val work = mapOf("auth1_session" to """{"token":"work-token"}""")
        val personal = mapOf("auth1_session" to """{"token":"personal-token"}""", "last-internal-org-for-external-org-v1-me" to "\"org_me\"")

        val credential = requireNotNull(reader(listOf(noToken, work, personal)).find()).credential

        assertEquals("work-token", credential.token)
        assertNull(credential["organization"])
    }

    @Test
    fun `should find no key when no profile keeps a token for the site`() {
        assertNull(reader(emptyList()).find())
        assertNull(reader(listOf(mapOf("auth1_session" to "not json"))).find())
        assertNull(reader(listOf(mapOf("auth1_session" to """{"other":"x"}"""))).find())
    }

    @Test
    fun `should read a key with no path as it is, a JSON string unquoted`() {
        val plain = """{"browserStorage":{"origin":"https://app.devin.ai","values":{"token":{"key":"session"}}}}"""
        assertEquals("plain", reader(listOf(mapOf("session" to "plain")), plain).find()?.credential?.token)
        assertEquals("quoted", reader(listOf(mapOf("session" to "\"quoted\"")), plain).find()?.credential?.token)
    }

    @Test
    fun `should take the first of several matching keys in name order`() {
        val store = mapOf(
            "auth1_session" to """{"token":"t"}""",
            "last-internal-org-for-external-org-v1-b" to "\"org_b\"",
            "last-internal-org-for-external-org-v1-a" to "\"org_a\"",
        )
        assertEquals("org_a", reader(listOf(store)).find()?.credential?.get("organization"))
    }

    @Test
    fun `should name the site in the lookup order and write the lookup back as it came`() {
        val lookup = lookup(storageLookup)
        assertEquals(listOf("Browser storage · app.devin.ai"), lookup.lookupOrder)
        assertEquals(lookup, CredentialLookup.from(lookup.toJson()))
    }

    @Test
    fun `should refuse a lookup that names no token`() {
        assertThrows<DefinitionError> {
            lookup("""{"browserStorage":{"origin":"https://app.devin.ai","values":{"organization":{"key":"org"}}}}""")
        }
    }

    @Test
    fun `should send the browser's token to the definition's host through a data source`() {
        val store = mapOf("auth1_session" to """{"token":"auth1_abc"}""", "last-internal-org-for-external-org-v1-acme" to "\"org_123\"")
        val finders = CredentialFinders(
            providerId = "devin", home = "/nowhere", environment = { null }, security = FakeSecurity { SecurityResult(1, "") },
            secrets = null, database = FakeDatabase { _, _ -> emptyList() }, browserCookies = FakeCookies(),
            browserStorage = FakeStorage(listOf(store)),
        )

        val credential = finders.reader(lookup(storageLookup)).find()?.credential

        assertEquals("https://app.devin.ai/api/org_123/usage", Template.fill("https://app.devin.ai/api/{{organization}}/usage", credential))
        assertEquals("Bearer auth1_abc", Template.fill("Bearer {{token}}", credential))
    }
}
