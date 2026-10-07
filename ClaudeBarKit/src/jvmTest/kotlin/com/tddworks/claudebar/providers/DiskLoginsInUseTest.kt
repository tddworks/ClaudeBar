package com.tddworks.claudebar.providers

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.io.File

/** The *In use* record on disk: one file per provider, holding a folder, read by the shell on every `claude` / `codex`. */
class DiskLoginsInUseTest {
    private val folder = TestDefinitions.folder("in-use")
    private val root = File(folder, "in-use").path

    @AfterEach
    fun cleanUp() {
        folder.deleteRecursively()
    }

    @Test
    fun `should use the plain login when nothing is recorded in use`() {
        assertNull(DiskLoginsInUse(root).folder("claude"))
    }

    @Test
    fun `should record a chosen login's folder as a plain path the shell can read`() {
        val record = DiskLoginsInUse(root)

        record.use("/Users/you/.claude-work/", "claude")

        assertEquals("/Users/you/.claude-work", File(record.file("claude")).readText())
        assertEquals("/Users/you/.claude-work", record.folder("claude"))
    }

    @Test
    fun `should leave an empty record when the person goes back to the plain login`() {
        val record = DiskLoginsInUse(root)
        record.use("/Users/you/.claude-work", "claude")

        record.use(null, "claude")

        assertEquals("", File(record.file("claude")).readText())
        assertNull(record.folder("claude"))
    }

    @Test
    fun `should keep a separate in-use record for each provider`() {
        val record = DiskLoginsInUse(root)

        record.use("/tmp/codex-work", "codex")

        assertEquals("/tmp/codex-work", record.folder("codex"))
        assertNull(record.folder("claude"))
    }
}
