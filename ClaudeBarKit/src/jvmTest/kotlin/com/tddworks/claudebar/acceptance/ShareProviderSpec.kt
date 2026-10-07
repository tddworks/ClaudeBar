package com.tddworks.claudebar.acceptance

import com.tddworks.claudebar.providers.ProviderCatalog
import com.tddworks.claudebar.providers.ProviderDraft
import com.tddworks.claudebar.providers.TestDefinitions
import com.tddworks.claudebar.providers.exported
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Feature: Export and import a provider
 *
 * USER_JOURNEYS §5 — Lin shares her team's gateway; a teammate imports it.
 */
class ShareProviderSpec {
    private val root = TestDefinitions.folder("share-spec")

    @AfterEach
    fun cleanUp() {
        root.deleteRecursively()
    }

    // Scenario: Importing a CLI provider asks first

    @Test
    fun `should show the person the command and save nothing until they add an imported CLI provider`() {
        // Given a provider file whose data source is a CLI command
        val draft = ProviderDraft(ProviderDraft.Start.Cli)
        draft.command = "teamtool usage --json"
        draft.measure = ProviderDraft.Measure.PercentLeft
        draft.remaining = "$.left"
        draft.name = "Team Tool"
        val file = draft.definition("custom-team-tool-abc123").exported()
        val catalog = ProviderCatalog(TestDefinitions.builtIns, File(root, "providers").path, File(root, "extensions").path)

        // When it is imported — reviewed first
        val review = catalog.review(file)

        // Then the command is shown, and nothing is saved until the person adds it
        assertEquals(listOf("teamtool usage --json"), review.runs)
        assertTrue(catalog.custom().isEmpty())
        catalog.import(review)
        assertEquals(listOf("Team Tool"), catalog.custom().map { it.profile.name })
    }
}
