package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.FileCall
import com.tddworks.claudebar.datasources.PathPattern
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** The FileFetcher case of PathPatternTests: a `*` path reads the most recently changed match. */
class FileFetchTest {
    @TempDir
    lateinit var home: File

    private fun write(relative: String, text: String, ago: Long) {
        val file = File(home, relative)
        file.parentFile.mkdirs()
        file.writeText(text)
        file.setLastModified(System.currentTimeMillis() - ago * 1000)
    }

    @Test
    fun `should read the newest matching file and not be ready when nothing matches`() = runTest {
        write("IDE/A1/quota.xml", "old", ago = 3600)
        write("IDE/B2/quota.xml", "new", ago = 10)

        val found = FileFetcher(FileCall(PathPattern("~/IDE/*/quota.xml")), home.path) { null }
        assertTrue(found.isReady())
        assertEquals("new", found.fetch(null).text)

        val missing = FileFetcher(FileCall(PathPattern("~/IDE/*/other.xml")), home.path) { null }
        assertFalse(missing.isReady())
    }
}
