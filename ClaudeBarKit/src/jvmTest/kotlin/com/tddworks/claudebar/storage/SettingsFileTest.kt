package com.tddworks.claudebar.storage

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

class SettingsFileTest {
    @TempDir
    lateinit var dir: File

    private val path get() = File(dir, "settings.json").path
    private fun settings() = SettingsFile(path)

    @Test
    fun `should have no settings when settings json does not exist`() {
        assertNull(settings().read("app.themeMode"))
    }

    @Test
    fun `should create settings json and keep the value written`() {
        settings().write("greeting", JsonPrimitive("hello"))
        assertEquals("hello", settings().string("greeting"))
    }

    @Test
    fun `should keep the other settings when one is written`() {
        File(path).writeText("""{"existing":"value"}""")
        settings().write("added", JsonPrimitive("new"))
        assertEquals("value", settings().string("existing"))
        assertEquals("new", settings().string("added"))
    }

    @Test
    fun `should forget a setting written as nothing`() {
        settings().write("gone", JsonPrimitive("soon"))
        settings().write("gone", null)
        assertNull(settings().read("gone"))
    }

    @Test
    fun `should find a setting nested by its dotted name and create the sections it needs`() {
        settings().write("claude.probe.mode", JsonPrimitive("cli"))
        assertEquals("cli", settings().string("claude.probe.mode"))
    }

    @Test
    fun `should keep a nested setting's neighbours when it changes`() {
        settings().write("app.theme", JsonPrimitive("dark"))
        settings().write("app.overview", JsonPrimitive(true))
        settings().write("app.theme", JsonPrimitive("light"))
        assertEquals("light", settings().string("app.theme"))
        assertEquals(true, settings().read("app.overview")!!.jsonPrimitive.boolean)
    }

    @Test
    fun `should keep yes-or-no, whole, decimal and list settings as written`() {
        settings().write("a.flag", JsonPrimitive(false))
        settings().write("a.count", JsonPrimitive(42))
        settings().write("a.rate", JsonPrimitive(3.14))
        settings().writeJson("a.regions", """["us-east-1","eu-west-1"]""")
        assertEquals(false, settings().read("a.flag")!!.jsonPrimitive.boolean)
        assertEquals(42, settings().read("a.count")!!.jsonPrimitive.int)
        assertEquals(3.14, settings().read("a.rate")!!.jsonPrimitive.double)
        assertEquals("""["us-east-1","eu-west-1"]""", settings().readJson("a.regions"))
    }

    @Test
    fun `should have no settings when settings json is broken, and repair it on the next write`() {
        File(path).writeText("{ not json")
        assertNull(settings().read("anything"))
        settings().write("fixed", JsonPrimitive("yes"))
        assertEquals("yes", settings().string("fixed"))
    }

    @Test
    fun `should create the folders settings json lives in`() {
        val nested = SettingsFile(File(dir, "a/b/settings.json").path)
        nested.write("made", JsonPrimitive("created"))
        assertEquals("created", nested.string("made"))
    }

    @Test
    fun `should give back every setting in the file`() {
        File(path).writeText("""{"version":1,"app":{"theme":"dark"}}""")
        val all = settings().readAll()
        assertEquals(1, all["version"]!!.jsonPrimitive.int)
        assertEquals("dark", all["app"]!!.jsonObject["theme"]!!.jsonPrimitive.content)
        assertTrue(SettingsFile(File(dir, "none.json").path).readAll().isEmpty())
    }

    @Test
    fun `should write sorted names with two-space indents`() {
        settings().write("b", JsonPrimitive(1))
        settings().writeJson("a", """{"y":[true],"x":"s"}""")
        assertEquals(
            "{\n  \"a\" : {\n    \"x\" : \"s\",\n    \"y\" : [\n      true\n    ]\n  },\n  \"b\" : 1\n}\n",
            File(path).readText(),
        )
    }

    @Test
    fun `should leave an unknown section alone`() {
        File(path).writeText("""{"future":{"thing":[1,2]}}""")
        settings().write("app.theme", JsonPrimitive("dark"))
        assertEquals(JsonArray(listOf(JsonPrimitive(1), JsonPrimitive(2))), (settings().read("future") as JsonObject)["thing"])
    }
}
