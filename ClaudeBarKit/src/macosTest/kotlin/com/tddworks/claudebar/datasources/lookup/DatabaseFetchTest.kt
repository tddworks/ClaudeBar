package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.PathPattern
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SQLiteCall
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * `fetch.sqlite` — rows of another app's own database as the answer, read through the same
 * read-only query as the `sqlite` key lookup (ENGINE_DESIGN §2.9). The database is never written.
 */
class DatabaseFetchTest {
    private val scratch = Scratch()

    @AfterTest
    fun cleanUp() = scratch.remove()

    private fun fetcher(path: String, query: String) = SQLiteFetcher(SQLiteCall(PathPattern(path), query), SystemSQLite(), scratch.root) { null }

    private fun rows(response: Response): List<Map<String, String>> =
        (Json.parseToJsonElement(response.text) as JsonArray).map { row -> (row as JsonObject).mapValues { it.value.jsonPrimitive.content } }

    @Test
    fun `should answer with the rows the query reads with each column as text`() = runBlocking {
        scratch.database("""CREATE TABLE ItemTable(key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('plan', '{"planName":"Pro"}'), ('other', 'x');""")

        val response = fetcher("~/state.vscdb", "SELECT value FROM ItemTable WHERE key = 'plan'").fetch(null)

        assertEquals(listOf(mapOf("value" to """{"planName":"Pro"}""")), rows(response))
    }

    @Test
    fun `should read text an app stored as a UTF-8 BLOB`() = runBlocking {
        scratch.database("CREATE TABLE ItemTable(key TEXT, value BLOB); INSERT INTO ItemTable VALUES ('plan', X'${hex("""{"planName":"Pro"}""".encodeToByteArray())}');")

        val response = fetcher("~/state.vscdb", "SELECT value FROM ItemTable").fetch(null)

        assertEquals(listOf(mapOf("value" to """{"planName":"Pro"}""")), rows(response))
    }

    @Test
    fun `should read text an app stored as a UTF-16 BLOB`() = runBlocking {
        scratch.database("CREATE TABLE ItemTable(key TEXT, value BLOB); INSERT INTO ItemTable VALUES ('plan', X'${hex(utf16("""{"planName":"Pro"}"""))}');")

        val response = fetcher("~/state.vscdb", "SELECT value FROM ItemTable").fetch(null)

        assertEquals(listOf(mapOf("value" to """{"planName":"Pro"}""")), rows(response))
    }

    @Test
    fun `should answer with no rows when the query finds nothing`() = runBlocking {
        scratch.database("CREATE TABLE ItemTable(key TEXT, value TEXT);")

        val response = fetcher("~/state.vscdb", "SELECT value FROM ItemTable").fetch(null)

        assertEquals(emptyList(), rows(response))
    }

    @Test
    fun `should refuse a query that would change the app's database and leave it as it was`() = runBlocking {
        val file = scratch.database("CREATE TABLE ItemTable(key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('a', 'b');")
        val before = scratch.bytes(file)

        assertFailsWith<UsageError> { runBlocking { fetcher("~/state.vscdb", "DELETE FROM ItemTable").fetch(null) } }
        fetcher("~/state.vscdb", "SELECT value FROM ItemTable").fetch(null)
        assertContentEquals(before, scratch.bytes(file))
    }

    @Test
    fun `should be configured only while the database is there`() {
        assertFalse(fetcher("~/state.vscdb", "SELECT 1").isReady())
        scratch.database("CREATE TABLE t(v TEXT);")
        assertTrue(fetcher("~/state.vscdb", "SELECT 1").isReady())
    }

    @Test
    fun `should read the most recently changed database a star matches`() = runBlocking {
        val old = scratch.database("CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('old');", "App/Old/state.vscdb")
        scratch.changed(old, secondsAgo = 3600.0)
        scratch.database("CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('new');", "App/New/state.vscdb")

        val response = fetcher("~/App/*/state.vscdb", "SELECT v FROM t").fetch(null)

        assertEquals(listOf(mapOf("v" to "new")), rows(response))
    }

    @Test
    fun `should come from a definition and name no host and run nothing`() {
        val fetch = Fetch.from(Json.parseToJsonElement("""{"sqlite":{"path":"~/state.vscdb","query":"SELECT value FROM ItemTable"}}"""))
        assertEquals(Fetch.Sqlite(SQLiteCall(PathPattern("~/state.vscdb"), "SELECT value FROM ItemTable")), fetch)
        assertEquals(fetch, Fetch.from(fetch.toJson()))
    }

    @Test
    fun `should find a key an app stored as a UTF-16 BLOB`() {
        scratch.database("CREATE TABLE items(value BLOB); INSERT INTO items VALUES (X'${hex(utf16("secret-token"))}');")

        val reader = SQLiteReader(
            SQLiteCredential(PathPattern("~/state.vscdb"), "SELECT value AS token FROM items", mapOf("token" to "$.token")),
            SystemSQLite(), scratch.root,
        ) { null }

        assertEquals("secret-token", reader.find()?.credential?.token)
    }
}
