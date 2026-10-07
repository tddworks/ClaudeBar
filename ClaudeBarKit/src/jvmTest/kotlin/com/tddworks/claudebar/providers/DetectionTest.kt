package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * A definition on disk is a provider (TARGET_ARCHITECTURE §10): the bundle,
 * `~/.claudebar/providers` and `~/.claudebar/extensions` are read the same way, ordered by
 * each definition's own `order`, and no code lists one.
 */
class DetectionTest {
    private val root = TestDefinitions.folder("detection")
    private val custom = File(root, "providers")
    private val extensions = File(root, "extensions")

    @AfterEach
    fun cleanUp() {
        root.deleteRecursively()
    }

    private fun detect() = ProviderCatalog(TestDefinitions.builtIns, custom.path, extensions.path).detect()

    /** A custom definition file, as *Add Provider* saves it. */
    private fun write(custom: String, name: String, order: Int? = null) {
        val id = custom
        this.custom.mkdirs()
        val place = order?.let { ""","order":$it""" } ?: ""
        File(this.custom, "$id.json").writeText(
            """
            {"profile":{"id":"$id","name":"$name"}$place,"defaultDataSource":"api",
             "dataSources":[{"kind":"api","fetch":{"file":{"path":"~/x.json"}},"mapping":{"json":{"quotas":[]}}}]}
            """.trimIndent(),
        )
    }

    @Test
    fun `should find every built-in in today's order without a list in Swift`() {
        val ids = detect().map { it.id }
        assertEquals(
            listOf("claude", "codex", "gemini", "antigravity", "zai", "copilot", "bedrock", "ampcode", "kimi", "kiro",
                "cursor", "minimax", "deepseek", "openrouter", "vercel-gateway", "alibaba", "mistral", "opencode-go",
                "omp", "grok", "commandcode", "cline", "warp", "devin", "windsurf", "jetbrains", "openai"),
            ids,
        )
        assertTrue(detect().all { it.profile.origin == ProviderProfile.Origin.BUILT_IN })
    }

    @Test
    fun `should find a provider someone made, after the built-ins when it names no order`() {
        write(custom = "custom-zeta", name = "Zeta")
        write(custom = "custom-alpha", name = "Alpha")

        val detected = detect()

        assertEquals(listOf("custom-alpha", "custom-zeta"), detected.takeLast(2).map { it.id })
        assertEquals(ProviderProfile.Origin.CUSTOM, detected.last().profile.origin)
    }

    @Test
    fun `should place a provider by its own order`() {
        write(custom = "custom-early", name = "Early", order = 15)

        assertEquals(listOf("claude", "custom-early", "codex"), detect().map { it.id }.take(3))
    }

    @Test
    fun `should keep a built-in's id for the built-in`() {
        write(custom = "warp", name = "Not Warp")

        val warps = detect().filter { it.id == "warp" }

        assertEquals(1, warps.size)
        assertEquals("Warp", warps.first().profile.name)
    }

    @Test
    fun `should skip a file that isn't a definition and find the rest`() {
        custom.mkdirs()
        File(custom, "broken.json").writeText("not json")
        write(custom = "custom-fine", name = "Fine")

        assertTrue(detect().any { it.id == "custom-fine" })
    }

    @Test
    fun `should find an extension as a provider`() {
        TestDefinitions.exampleExtension.copyRecursively(File(extensions, "example-provider"))

        val example = detect().firstOrNull { it.profile.origin == ProviderProfile.Origin.EXTENSION }
        assertNotNull(example)
        assertEquals("Example Provider", example!!.profile.name)
    }
}
