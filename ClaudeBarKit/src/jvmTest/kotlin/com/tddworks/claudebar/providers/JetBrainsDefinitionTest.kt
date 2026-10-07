package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.commands
import com.tddworks.claudebar.datasources.process.InMemoryLoginFolders
import com.tddworks.claudebar.datasources.testDataSources
import com.tddworks.claudebar.datasources.urls
import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Instant
import kotlin.math.abs

/** JetBrains AI as data: the AI quota a JetBrains IDE saves on this Mac, from the IDE used last, read by `jetbrains-quota.js`. */
class JetBrainsDefinitionTest {
    /** The quota file as an IDE writes it: JSON inside HTML-encoded XML attributes. */
    private fun quota(current: String = "7478.3", maximum: String = "1000000", next: String? = "2026-11-01T14:00:54.939Z"): String {
        fun encoded(json: String) = json.replace("&", "&amp;").replace("\"", "&quot;").replace("\n", "&#10;")
        val info = """
            {
              "type": "Available",
              "current": "$current",
              "maximum": "$maximum",
              "until": "2026-11-09T21:00:00Z",
              "tariffQuota": { "current": "$current", "maximum": "$maximum", "available": "0" }
            }
        """.trimIndent()
        val refill = next?.let {
            """
            {
              "type": "Known",
              "next": "$it",
              "tariff": { "amount": "$maximum", "duration": "PT720H" }
            }
            """.trimIndent()
        }
        val refillOption = refill?.let { "<option name=\"nextRefill\" value=\"${encoded(it)}\" />" } ?: ""
        return """
            |<application>
            |  <component name="AIAssistantQuotaManager2">
            |    <option name="quotaInfo" value="${encoded(info)}" />
            |    $refillOption
            |  </component>
            |</application>
        """.trimMargin()
    }

    private val home = TestDefinitions.folder("jetbrains")

    @AfterEach
    fun cleanUp() {
        home.deleteRecursively()
    }

    /** A quota file in one IDE's folder, last changed [ago] seconds before now. */
    private fun ide(folder: String, xml: String, ago: Long = 0) {
        val file = File(home, "Library/Application Support/$folder/options/AIAssistantQuotaManager2.xml")
        file.parentFile.mkdirs()
        file.writeText(xml)
        file.setLastModified(System.currentTimeMillis() - ago * 1000)
    }

    private fun make(): Provider {
        val definition = TestDefinitions.builtIn("jetbrains")
        val connections = testDataSources(home = home.path, now = { System.currentTimeMillis() / 1000.0 })
        return Provider(
            definition = definition, settings = InMemoryProviderSettings(),
            makeDataSource = { source, _ -> connections.make(source, definition.id, null, TestDefinitions.builtIns::script) },
            folders = InMemoryLoginFolders(), paths = HomePaths(home.path), isExecutable = { true }, locate = { it },
        )
    }

    private fun RefreshOutcome.failure(): UsageError {
        assertTrue(this is RefreshOutcome.Failed, "expected a failure, got $this")
        return (this as RefreshOutcome.Failed).error
    }

    @Test
    fun `should be JetBrains AI, off until turned on, reading only this Mac`() {
        val jetbrains = make()
        assertEquals("jetbrains", jetbrains.id)
        assertEquals("JetBrains AI", jetbrains.name)
        assertEquals(false, jetbrains.plainIsInLineup)
        val source = jetbrains.definition.dataSources.firstOrNull()
        assertNotNull(source)
        assertTrue(source!!.fetch.urls.isEmpty())
        assertTrue(source.fetch.commands.isEmpty())
    }

    @Test
    fun `should show the AI credits left this month and when they refill`() {
        ide("JetBrains/IntelliJIdea2025.3", quota(current = "250000", maximum = "1000000"))

        val usage = make().refreshPlain().usage()

        val credits = usage.quotas.firstOrNull()
        assertNotNull(credits)
        assertEquals(QuotaType.TimeLimit("AI credits"), credits!!.quotaType)
        assertEquals(75.0, credits.percentRemaining)
        val refill = Instant.parse("2026-11-01T14:00:54Z").epochSecond + 0.939
        assertTrue(abs((credits.resetsAtSeconds ?: 0.0) - refill) < 0.001, "${credits.resetsAtSeconds}")
        assertEquals(2_592_000.0, credits.windowSeconds ?: -1.0)
    }

    @Test
    fun `should read the IDE used last, Android Studio included`() {
        ide("JetBrains/IntelliJIdea2025.3", quota(current = "100000"), ago = 3600)
        ide("JetBrains/PyCharm2025.2", quota(current = "900000"), ago = 86400)
        ide("Google/AndroidStudio2025.1", quota(current = "500000"), ago = 60)

        val usage = make().refreshPlain().usage()

        assertEquals(50.0, usage.quotas.firstOrNull()?.percentRemaining)
    }

    @Test
    fun `should show the quota with no refill time when the IDE saved none`() {
        ide("JetBrains/GoLand2025.3", quota(current = "0", next = null))

        val usage = make().refreshPlain().usage()

        assertEquals(100.0, usage.quotas.firstOrNull()?.percentRemaining)
        assertNull(usage.quotas.firstOrNull()?.resetsAtSeconds)
    }

    @Test
    fun `should not be set up when no JetBrains IDE has saved a quota`() {
        val jetbrains = make()
        assertFalse(runBlocking { jetbrains.isAvailable(jetbrains.defaultAccount) })
    }

    @ParameterizedTest
    @ValueSource(strings = ["<application/>", "not xml at all"])
    fun `should fail reading the quota when the IDE's file has none`(xml: String) {
        ide("JetBrains/WebStorm2025.3", xml)
        val jetbrains = make()
        val account = jetbrains.defaultAccount
        jetbrains.refreshNow(account).failure()
        assertEquals(DataSourceError.Step.MAPPING, account.lastFailedStep)
    }

    /** How an IDE saves a quota it doesn't know, or failed to get. */
    private fun state(quota: String): String = """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="nextRefill" value="{&#10;  &quot;type&quot;: &quot;Error&quot;,&#10;  &quot;exception&quot;: &quot;&quot;,&#10;  &quot;previous&quot;: null&#10;}" />
            <option name="quotaInfo" value="$quota" />
          </component>
        </application>
    """.trimIndent()

    @Test
    fun `should ask to sign in to JetBrains AI when the IDE knows no quota`() {
        ide("JetBrains/IntelliJIdea2026.1", state("{&#10;  &quot;type&quot;: &quot;Unknown&quot;&#10;}"))
        val jetbrains = make()
        val error = jetbrains.refreshNow(jetbrains.defaultAccount).failure()
        assertTrue(error is UsageError.SessionExpired, "$error")
        assertEquals("Sign in to JetBrains AI in your IDE, then use AI Assistant once.", (error as UsageError.SessionExpired).hint)
    }

    @Test
    fun `should say the IDE couldn't get the quota when it saved an error`() {
        ide("JetBrains/IntelliJIdea2025.1", state("{&#10;  &quot;type&quot;: &quot;Error&quot;,&#10;  &quot;exception&quot;: &quot;&quot;&#10;}"))
        val jetbrains = make()
        assertEquals(
            UsageError.ExecutionFailed("Your JetBrains IDE couldn't get the AI quota. Open AI Assistant in it to try again."),
            jetbrains.refreshNow(jetbrains.defaultAccount).failure(),
        )
    }
}
