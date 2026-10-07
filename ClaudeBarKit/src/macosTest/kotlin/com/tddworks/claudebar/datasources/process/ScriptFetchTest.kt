package com.tddworks.claudebar.datasources.process

import com.tddworks.claudebar.datasources.DataSource
import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.ScriptCall
import com.tddworks.claudebar.datasources.SecretStore
import com.tddworks.claudebar.datasources.commands
import com.tddworks.claudebar.datasources.systemDataSources
import com.tddworks.claudebar.datasources.urls
import com.tddworks.claudebar.quotas.QuotaType
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import platform.Foundation.NSFileManager
import platform.Foundation.NSFilePosixPermissions
import platform.Foundation.NSNumber
import platform.Foundation.NSString
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.NSUUID
import platform.Foundation.writeToFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * `script` — a script run with `/bin/sh` from its own folder, its settings in its environment
 * and its secrets from the vault: what an extension's section runs. Run for real, in a
 * temporary folder: the fetcher's response, then the same fetch made live by the factory and
 * its answer mapped, as the Swift suite did.
 */
class ScriptFetchTest {
    private val folder = NSTemporaryDirectory().trimEnd('/') + "/script-fetch-" + NSUUID().UUIDString
    private val files = NSFileManager.defaultManager

    private class Vault(private val values: Map<String, String>) : SecretStore {
        override fun secret(name: String, provider: String): String? = values["$provider.$name"]
    }

    @AfterTest
    fun removeFolder() {
        files.removeItemAtPath(folder, null)
    }

    @OptIn(kotlinx.cinterop.BetaInteropApi::class)
    private fun write(name: String, text: String, executable: Boolean = false) {
        files.createDirectoryAtPath(folder, withIntermediateDirectories = true, attributes = null, error = null)
        val path = "$folder/$name"
        @Suppress("CAST_NEVER_SUCCEEDS")
        (text as NSString).writeToFile(path, atomically = true, encoding = NSUTF8StringEncoding, error = null)
        if (executable) files.setAttributes(mapOf<Any?, Any?>(NSFilePosixPermissions to NSNumber(int = 493)), path, null)
    }

    private fun script(name: String, body: String) = write(name, "#!/bin/sh\n$body\n", executable = true)

    private fun fetcher(call: String, secrets: Map<String, String> = emptyMap()): ScriptFetcher =
        ScriptFetcher(
            Json.decodeFromString(ScriptCall.serializer(), call), "ext-acme", Vault(secrets),
            CommandFetcher.system(MacProcesses.host), MacFiles,
        )

    /** The data source the factory makes on this Mac for a script fetch, its answer mapped to a weekly quota. */
    private fun source(fetch: String, secrets: Map<String, String> = emptyMap()): DataSource {
        val json = """
        {"kind":"quotas","fetch":{"script":$fetch},
         "mapping":{"json":{"quotas":[{"kind":"weekly","at":"$.weekly","leftPercent":"left"}]}}}
        """
        return systemDataSources().make(DataSourceDefinition.from(Json.parseToJsonElement(json)), "ext-acme", Vault(secrets))
    }

    @Test
    fun `should show what a script prints when it runs from its own folder`() = runBlocking {
        script("probe.sh", "cat left.json")
        write("left.json", """{"weekly":{"left":62}}""")

        val response = fetcher("""{"run":"./probe.sh","folder":"$folder"}""").fetch(null)
        val usage = source("""{"run":"./probe.sh","folder":"$folder"}""").fetchUsage()

        assertEquals("""{"weekly":{"left":62}}""", response.text)
        assertEquals(62.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should hand a script its settings as environment variables and its secrets from the vault`() = runBlocking {
        script("probe.sh", """echo "{\"weekly\":{\"left\":${'$'}{#CLAUDEBAR_API_KEY}${'$'}CLAUDEBAR_REGION}}"""")

        val call = """{"run":"./probe.sh","folder":"$folder","environment":{"CLAUDEBAR_REGION":"0"},"secrets":{"CLAUDEBAR_API_KEY":"apiKey"}}"""
        val response = fetcher(call, mapOf("ext-acme.apiKey" to "sk-123")).fetch(null)
        val usage = source(call, mapOf("ext-acme.apiKey" to "sk-123")).fetchUsage()

        // ${#KEY} is the key's length (6), then the region "0": 60% left.
        assertEquals("""{"weekly":{"left":60}}""", response.text.trim())
        assertEquals(60.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should fail at the fetch step when the script fails`() = runBlocking {
        script("probe.sh", "exit 3")

        val failure = assertFailsWith<CLIExitError> { fetcher("""{"run":"./probe.sh","folder":"$folder"}""").fetch(null) }
        val error = assertFailsWith<DataSourceError> { source("""{"run":"./probe.sh","folder":"$folder"}""").fetchUsage() }

        assertEquals(3, failure.exitCode)
        assertEquals(DataSourceError.Step.FETCH, error.step)
    }

    @Test
    fun `should not be ready when the script is not there`() {
        files.createDirectoryAtPath(folder, withIntermediateDirectories = true, attributes = null, error = null)

        assertFalse(fetcher("""{"run":"./missing.sh","folder":"$folder"}""").isReady())
        assertFalse(source("""{"run":"./missing.sh","folder":"$folder"}""").isReady())
    }

    @Test
    fun `should declare only the script's own command as what it reaches and no URL`() {
        val fetch = Fetch.from(Json.parseToJsonElement("""{"script":{"run":"./probe.sh","folder":"/tmp/x"}}"""))

        assertEquals(listOf(listOf("/bin/sh", "-c", "./probe.sh")), fetch.commands)
        assertTrue(fetch.urls.isEmpty())
    }
}
