package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.io.File

/**
 * The engine — everything that touches this Mac, built once and the same for every provider
 * (TARGET_ARCHITECTURE §10). A definition uses only what its cases ask for; a capability is run
 * for whichever definition declares it.
 */
class EngineTest {
    private val stub = StubbedProvider()

    @AfterEach
    fun cleanUp() = stub.cleanUp()

    /** The guest-pass runners the engine was asked for, by the CLI each runs. */
    private val passes = mutableListOf<String>()

    private object NoPasses : GuestPassSource {
        override suspend fun isAvailable() = true
        override suspend fun fetch(): GuestPass = GuestPass(referralURL = "https://claude.ai/referral")
    }

    private fun engine(settings: InMemoryProviderSettings = InMemoryProviderSettings()) = Engine(
        settings = settings,
        connections = stub.connections(),
        home = stub.home,
        environment = { null },
        folders = stub.folders,
        paths = HomePaths(stub.home),
        isExecutable = { true },
        locate = { it },
        vault = MemoryVault(),
        guestPasses = { cli, _ ->
            passes += cli()
            NoPasses
        },
        now = { 0.0 },
    )

    private fun factory(engine: Engine = engine()) = ProviderFactory(engine, TestDefinitions.builtIns)

    @Test
    fun `should make a provider of every detected definition, in lineup order`() {
        val definitions = ProviderCatalog(TestDefinitions.builtIns, File(stub.home, "providers").path, File(stub.home, "extensions").path).detect()

        val providers = factory().make(definitions)

        assertEquals(definitions.map { it.id }, providers.map { it.id })
        assertEquals("claude", providers.first().id)
    }

    @Test
    fun `should give guest passes to the definition that declares them, at its CLI location`() {
        val settings = InMemoryProviderSettings()
        settings.setCLIPath("/opt/claude", "claude")
        val make = factory(engine(settings))

        val claude = make.make(TestDefinitions.builtIn("claude"))
        val codex = make.make(TestDefinitions.builtIn("codex"))

        assertNotNull(claude.defaultAccount.guestPasses)
        assertNull(codex.defaultAccount.guestPasses)
        assertEquals("/opt/claude", passes.last())
    }

    @Test
    fun `should run guest passes with the definition's own CLI when the person chose no location`() {
        factory().make(TestDefinitions.builtIn("claude"))

        assertEquals("claude", passes.last())
    }

    @Test
    fun `should find a custom provider's definition by its lineup id once it is made`() {
        val json = """
        {"profile":{"id":"custom-engine-test","name":"Engine Test"},"defaultDataSource":"api",
         "dataSources":[{"kind":"api","fetch":{"file":{"path":"~/x.json"}},"mapping":{"json":{"quotas":[]}}}]}
        """
        val definition = ProviderDefinition.parse(json, ProviderProfile.Origin.CUSTOM)
        val make = factory()

        make.make(definition)

        assertEquals("Engine Test", make.definition("custom-engine-test")?.profile?.name)
    }

    @Test
    fun `should read guest passes as declared in the definition`() {
        assertEquals(listOf("/passes", "--allowed-tools", ""), TestDefinitions.builtIn("claude").guestPasses?.args)
        assertNull(TestDefinitions.builtIn("codex").guestPasses)
    }
}
