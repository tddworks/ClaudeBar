package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.DirectoryCall
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.PathPattern
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** A folder some tool fills with its logs: ready while it exists, answered with the names in it that match. */
class DirectoryFetchTest {
    @TempDir
    lateinit var home: File

    private fun folder(names: List<String>) {
        val logs = File(home, ".acme/logs")
        logs.mkdirs()
        for (name in names) File(logs, name).mkdirs()
    }

    @Test
    fun `should be ready and list the folder's matching entries in order when the folder exists`() = runTest {
        folder(listOf("session_2", "session_1", "other"))
        val fetcher = DirectoryFetcher(DirectoryCall(PathPattern("~/.acme/logs"), match = "^session_"), home.path) { null }

        assertTrue(fetcher.isReady())
        val body = Json.parseToJsonElement(fetcher.fetch(null).text) as JsonObject
        assertEquals(listOf("session_1", "session_2"), body["entries"]!!.jsonArray.map { it.jsonPrimitive.content })
    }

    @Test
    fun `should not be ready when the folder isn't there`() {
        val fetcher = DirectoryFetcher(DirectoryCall(PathPattern("~/.nowhere")), home.path) { null }
        assertFalse(fetcher.isReady())
    }

    @Test
    fun `should keep a folder fetch when the definition is written out and read back`() {
        val fetch = Fetch.Directory(DirectoryCall(PathPattern("~/.acme/logs"), match = "^session_"))
        assertEquals(fetch, Fetch.from(fetch.toJson()))
    }
}
