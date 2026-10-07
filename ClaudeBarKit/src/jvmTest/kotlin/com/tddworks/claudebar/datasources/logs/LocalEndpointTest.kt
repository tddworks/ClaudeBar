package com.tddworks.claudebar.datasources.logs

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File

/** `freeWhen.localEndpoint`: a base URL on this Mac means nobody bills per token. The first entry that answers decides. */
class LocalEndpointTest {
    @TempDir
    lateinit var dir: File

    private val url = listOf(listOf("$.env.BASE_URL"), listOf("$.routes[*].base_url", "$.routes[*].env.BASE_URL"))

    private fun isLocal(json: String?): Boolean {
        val file = File(dir, "config.json")
        file.delete()
        if (json != null) file.writeText(json)
        return LocalEndpoint(file.path, url).isLocal()
    }

    @Test
    fun `should count usage as billed when the config is missing or names no address`() {
        assertFalse(isLocal(null))
        assertFalse(isLocal("""{"account":{"email":"a@b.c"}}"""))
    }

    @Test
    fun `should count usage as free when the tool's route points at this Mac`() {
        assertTrue(isLocal("""{"env":{"BASE_URL":"http://localhost:11434"}}"""))
        assertTrue(isLocal("""{"env":{"BASE_URL":"http://127.0.0.1:1234/v1"}}"""))
    }

    @Test
    fun `should count usage as billed when the tool's route points at a paid gateway`() {
        assertFalse(isLocal("""{"env":{"BASE_URL":"https://gateway.example.com/api"}}"""))
    }

    @Test
    fun `should count usage as free when there is no route and any listed one points at this Mac`() {
        assertTrue(isLocal("""{"routes":[{"base_url":"https://api.example.com"},{"base_url":"http://127.0.0.1:8080"}]}"""))
        assertTrue(isLocal("""{"routes":[{"env":{"BASE_URL":"http://[::1]:11434"}}]}"""))
    }

    @Test
    fun `should go by the tool's route over its list of others, either way`() {
        // The list is a menu the tool may switch between; the route is the one it takes.
        assertFalse(isLocal("""{"env":{"BASE_URL":"https://gateway.example.com"},"routes":[{"base_url":"http://localhost:11434"}]}"""))
        assertTrue(isLocal("""{"env":{"BASE_URL":"http://127.0.0.1:11434"},"routes":[{"base_url":"https://api.example.com"}]}"""))
    }

    @ParameterizedTest
    @ValueSource(strings = ["http://localhost:11434", "http://LOCALHOST:1234", "https://models.localhost/v1", "http://0.0.0.0:8000"])
    fun `should recognise an address on this Mac`(url: String) {
        assertTrue(LocalEndpoint.isLoopback(url))
    }

    @ParameterizedTest
    @ValueSource(strings = ["https://api.example.com", "http://192.168.1.10:11434", "https://my-localhost.example.com/v1", "not a url"])
    fun `should not take another machine's address for this Mac`(url: String) {
        assertFalse(LocalEndpoint.isLoopback(url))
    }
}
