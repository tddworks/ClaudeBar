package com.tddworks.claudebar.datasources.lookup

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** The `jsonFile` cases of the Swift PathPatternTests: a `*` and a list in a key's path. */
class PathPatternLookupTest {
    @TempDir
    lateinit var home: File

    private fun write(relative: String, text: String, ago: Long) {
        val file = File(home, relative)
        file.parentFile.mkdirs()
        file.writeText(text)
        file.setLastModified(System.currentTimeMillis() - ago * 1000)
    }

    @Test
    fun `should find a key in the newest login file a star matches`() {
        write("profiles/old/auth.json", """{"token":"old"}""", ago = 3600)
        write("profiles/new/auth.json", """{"token":"new"}""", ago = 10)

        val lookup = lookup("""{"jsonFile":{"path":"~/profiles/*/auth.json","token":"$.token"}}""") as CredentialLookup.JsonFile
        val reader = JSONFileReader(lookup.file, home.path) { null }

        assertEquals("new", reader.find()?.credential?.token)
    }

    @Test
    fun `should list each place a key may be in the lookup order`() {
        val lookup = lookup("""{"jsonFile":{"path":["~/a/*/auth.json","~/b.json"],"token":"$.token"}}""")
        assertEquals(listOf("~/a/*/auth.json", "~/b.json"), lookup.lookupOrder)
    }
}
