package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * A login file owned by a CLI is renewed by running that CLI once the token is refused: the CLI
 * writes its own file, which is read again — ClaudeBar never writes it. The data source's retry
 * is the refresher's answer followed by a second read.
 */
class CLIRefreshTest {
    private val credentialJSON = """
    {"jsonFile":{"path":"~/.acme/creds.json","token":"$.access_token"},
     "refresh":{"cli":{"cli":"acme","input":"/quit\n","timeout":15}}}
    """

    @TempDir
    lateinit var home: File

    private val file get() = File(home, ".acme/creds.json")

    @BeforeEach
    fun stale() {
        file.parentFile.mkdirs()
        file.writeText("""{"access_token":"stale"}""")
    }

    private fun parts(): Pair<JSONFileReader, CredentialRefresh> {
        val (base, refresh) = CredentialFinders.split(lookup(credentialJSON))
        return JSONFileReader((base as CredentialLookup.JsonFile).file, home.path) { null } to refresh!!
    }

    private fun refresher(cli: FakeCLI) =
        CredentialFinders.refresher(parts().second, FakeNetwork(), makeExecutor = { cli }, now = { 0.0 })

    @Test
    fun `should renew a refused token by running the CLI and show usage with the file it wrote, never writing it ourselves`() = runTest {
        val cli = FakeCLI { file.writeText("""{"access_token":"fresh","note":"cli"}""") }
        val (reader, _) = parts()
        val refresher = refresher(cli)
        val stale = reader.find()!!.credential
        assertTrue(401 in refresher.retryStatuses)

        refresher.refresh(stale)

        assertEquals("fresh", reader.find()?.credential?.token)
        assertEquals(listOf("/quit\n"), cli.inputs)
        assertFalse(refresher.writesBack)
        // The CLI's own file, untouched by us.
        assertEquals("""{"access_token":"fresh","note":"cli"}""", file.readText())
    }

    @Test
    fun `should never run the CLI when the saved token still works`() {
        val cli = FakeCLI()
        val (reader, _) = parts()

        assertFalse(refresher(cli).isDue(reader.find()!!.credential))
        assertTrue(cli.inputs.isEmpty())
    }

    @Test
    fun `should ask to sign in again when the token is refused and the CLI is not installed`() = runTest {
        val (reader, _) = parts()

        val error = failure<UsageError> { refresher(FakeCLI(located = false)).refresh(reader.find()!!.credential) }

        assertEquals(UsageError.AuthenticationRequired, error)
    }

    @Test
    fun `should ask to sign in again when the CLI renews nothing`() = runTest {
        val cli = FakeCLI()
        val (reader, _) = parts()

        refresher(cli).refresh(reader.find()!!.credential)

        // Read again, the same refused token: the data source asks to sign in.
        assertEquals("stale", reader.find()?.credential?.token)
        assertEquals(1, cli.inputs.size)
    }

    @Test
    fun `should keep the CLI renewal when the definition is written out and read back`() {
        val credential = lookup(credentialJSON)
        assertEquals(credential, CredentialLookup.from(Json.parseToJsonElement(credential.toJson().toString()) as JsonObject))
        val refresh = (credential as CredentialLookup.Refreshing).refresh
        assertEquals("acme", (refresh as CredentialRefresh.Cli).call.cli)
    }
}
