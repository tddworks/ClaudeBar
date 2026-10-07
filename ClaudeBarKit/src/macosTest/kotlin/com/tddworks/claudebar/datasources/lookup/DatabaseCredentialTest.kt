package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.SecretStore
import com.tddworks.claudebar.datasources.Template
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.serialization.json.Json
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/**
 * `sqlite` — a key another app keeps in its own database, read without ever writing to it, on
 * macOS's own libsqlite3; and `{{token#jwt.claim}}` for what the key says.
 */
class DatabaseCredentialTest {
    private val token = "header.eyJzdWIiOiJ3b3JrLXVzZXIifQ.signature"
    private val scratch = Scratch()

    @AfterTest
    fun cleanUp() = scratch.remove()

    private fun reader(credential: String) = CredentialFinders(
        providerId = "acme", home = scratch.root, environment = { null }, security = SecurityTool { SecurityResult(1, "") },
        secrets = object : SecretStore {
            override fun secret(name: String, provider: String) = token
        },
        database = SystemSQLite(), browserCookies = BrowserCookieStores(scratch.root, SystemSQLite(), KeychainSafeStorage, CommonCryptoCookies, { 0.0 }, emptyList()),
        browserStorage = BrowserStorageStores(scratch.root, emptyList()),
    ).reader(CredentialLookup.from(Json.parseToJsonElement(credential)))

    @Test
    fun `should use a key kept in another app's database without ever changing that database`() {
        val file = scratch.database("CREATE TABLE items(key TEXT, value TEXT); INSERT INTO items VALUES ('auth', '$token');")
        val before = scratch.bytes(file)

        val credential = reader("""{"sqlite":{"path":"$file","query":"SELECT value AS token FROM items WHERE key = 'auth'","fields":{"token":"$.token"}}}""")
            .find()?.credential

        assertEquals("work-user::$token", Template.fill("{{token#jwt.sub}}::{{token}}", credential))
        assertContentEquals(before, scratch.bytes(file))
    }

    @Test
    fun `should refuse at finding the key a lookup that would change the other app's database`() {
        val file = scratch.database("CREATE TABLE items(value TEXT);")

        assertFailsWith<UsageError> {
            reader("""{"sqlite":{"path":"$file","query":"DELETE FROM items","fields":{"token":"$.token"}}}""").find()
        }
    }

    @Test
    fun `should ask to sign in when the other app's database holds no key`() {
        val file = scratch.database("CREATE TABLE items(key TEXT, value TEXT);")

        assertNull(reader("""{"sqlite":{"path":"$file","query":"SELECT value AS token FROM items","fields":{"token":"$.token"}}}""").find())
    }

    @Test
    fun `should send what the key says about its owner wherever the key was found`() {
        val credential = reader("""{"setting":"token"}""").find()?.credential

        assertEquals("work-user::$token", Template.fill("{{token#jwt.sub}}::{{token}}", credential))
    }

    @Test
    fun `should show the definition's hint in Settings and name the database file in the lookup order`() {
        val lookup = CredentialLookup.from(
            Json.parseToJsonElement("""{"sqlite":{"path":"~/x.db","query":"SELECT 1","fields":{},"hint":"Sign in again in Acme."}}"""),
        )
        assertEquals("Sign in again in Acme.", lookup.hint)
        assertEquals(listOf("~/x.db"), lookup.lookupOrder)
    }
}
