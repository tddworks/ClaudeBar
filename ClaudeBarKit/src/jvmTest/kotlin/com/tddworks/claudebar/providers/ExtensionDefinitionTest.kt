package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.mapping.Mapping
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.io.File

/**
 * An extension's `manifest.json`, read as a definition of origin *Extension*
 * (docs/features/extensions/design.md). The person's file stays as it is. What the example's
 * script shows once refreshed runs through `Provider`, and is the lifecycle's to test.
 */
class ExtensionDefinitionTest {
    private val root = TestDefinitions.folder("extensions")

    @AfterEach
    fun cleanUp() {
        root.deleteRecursively()
    }

    /** `docs/features/extensions/example-provider`, copied, its health check (a network call) taken out. */
    private fun example(): File {
        val folder = File(root, "example-provider")
        TestDefinitions.exampleExtension.copyRecursively(folder)
        val manifest = File(folder, "manifest.json")
        val json = Json.parseToJsonElement(manifest.readText()).jsonObject
        val sections = (json["sections"] as JsonArray).filter { (it as JsonObject)["type"] != JsonPrimitive("healthCheck") }
        manifest.writeText(JsonObject(json + ("sections" to JsonArray(sections))).toString())
        return folder
    }

    private fun read(folder: File) = Extensions.definition(File(folder, "manifest.json").readText(), folder.path)

    @Test
    fun `should show an extension under its manifest's name, symbol, colour and dashboard, marked as an extension`() {
        val definition = read(example())

        assertEquals("ext-example-provider", definition.id)
        assertEquals("Example Provider", definition.profile.name)
        assertEquals(ProviderProfile.Origin.EXTENSION, definition.profile.origin)
        assertEquals("cpu.fill", definition.profile.look.symbol)
        assertEquals(ProviderLook.RGB(1.0, 107.0 / 255, 53.0 / 255), definition.profile.look.color?.light)
        assertEquals("https://example.com/usage", definition.profile.links.dashboardTemplate)
        assertTrue(definition.together)
    }

    @Test
    fun `should offer an extension's config fields as its settings, a toggle as on or off`() {
        val settings = read(example()).settings.associateBy { it.id }

        assertEquals(Setting.Kind.Secret, settings["apiKey"]?.kind)
        assertEquals("https://api.example.com", settings["baseUrl"]?.default)
        assertEquals("100", settings["monthlyBudget"]?.default)
        val toggle = settings["verboseLogging"]?.kind as? Setting.Kind.Choice
        assertEquals(listOf("true", "false"), toggle?.options?.map { it.id }, "a toggle is a choice of on and off")
    }

    @Test
    fun `should run the extension's own script, with its key and settings, for each section it can read`() {
        val folder = example()
        val definition = read(folder)

        assertEquals(listOf("quotas"), definition.dataSources.map { it.kind })
        val call = (definition.dataSources[0].fetch as Fetch.Script).call
        assertEquals("./probe-quota.sh", call.run)
        assertEquals(folder.path, call.folder)
        assertEquals(mapOf("CLAUDEBAR_API_KEY" to "apiKey"), call.secrets)
        assertEquals("{{setting.baseUrl}}", call.environment["CLAUDEBAR_BASE_URL"])
        assertEquals(Mapping.Usage, definition.dataSources[0].mapping)
    }

    @Test
    fun `should check an extension's health by asking its URL within its timeout`() {
        val definition = Extensions.definition(
            """
            {"id":"up","name":"Up","version":"1","sections":[
              {"id":"health","type":"healthCheck","probe":{"builtIn":"healthCheck","url":"https://example.com/health","timeout":5}}]}
            """.trimIndent(),
            root.path,
        )

        val request = (definition.dataSources[0].fetch as Fetch.Http).request
        assertEquals("https://example.com/health", request.url)
        assertEquals(5.0, request.timeout)
    }

    @Test
    fun `should refuse an extension with no section it can read`() {
        assertThrows<Exception> {
            Extensions.definition(
                """{"id":"m","name":"M","version":"1","sections":[{"id":"m","type":"metricsRow","probe":{"command":"./m.sh"}}]}""",
                root.path,
            )
        }
    }

    @Test
    fun `should list every extension and skip one whose manifest is damaged`() {
        example()
        val broken = File(root, "broken").also { it.mkdirs() }
        File(broken, "manifest.json").writeText("{")

        assertEquals(listOf("ext-example-provider"), Extensions.catalog(root.path).map { it.id })
    }

    @Test
    fun `should not list a folder that has no manifest`() {
        File(root, "notes").mkdirs()

        assertTrue(Extensions.catalog(root.path).isEmpty())
    }

    @Test
    fun `should list no extensions when there is no extensions folder`() {
        assertTrue(Extensions.catalog(File(root, "missing").path).isEmpty())
    }

    @Test
    fun `should hand each setting to the script under a CLAUDEBAR_ name built from its id`() {
        val definition = Extensions.definition(
            """
            {"id":"names","name":"Names","version":"1",
             "config":[{"id":"apiKey","label":"Key","type":"secret"},{"id":"port","label":"Port","type":"number"},
                       {"id":"base-url","label":"URL","type":"string"},{"id":"monthlyBudget","label":"Budget","type":"number"}],
             "sections":[{"id":"quotas","type":"quotaGrid","probe":{"command":"./probe.sh"}}]}
            """.trimIndent(),
            root.path,
        )
        val call = (definition.dataSources[0].fetch as Fetch.Script).call

        assertEquals(setOf("CLAUDEBAR_API_KEY"), call.secrets.keys)
        assertEquals(setOf("CLAUDEBAR_PORT", "CLAUDEBAR_BASE_URL", "CLAUDEBAR_MONTHLY_BUDGET"), call.environment.keys)
    }
}
