package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.datasources.mapping.Mapping
import com.tddworks.claudebar.datasources.mapping.ScriptMapping
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.UUID

/** *Configured* — what `isReady` answers before anything runs. */
class ReadinessTest {
    private fun make(requiresFiles: List<String>): DataSource {
        val definition = DataSourceDefinition(
            kind = "file",
            fetch = Fetch.Http(HTTPRequest(url = "https://acme.test")),
            mapping = Mapping.Script(ScriptMapping("none.js")),
            requiresFiles = requiresFiles,
        )
        return testDataSources().make(definition, "acme")
    }

    @Test
    fun `should not be configured when a file it needs is missing`() {
        assertFalse(make(listOf("/no/such/acme/login.json")).isReady())
    }

    @Test
    fun `should be configured when the files it needs exist`() {
        val file = File(TEMP_HOME, "acme-${UUID.randomUUID()}.json")
        file.writeText("{}")
        try {
            assertTrue(make(listOf(file.path)).isReady())
        } finally {
            file.delete()
        }
    }
}
