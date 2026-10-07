package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The script engine itself, in the real JavaScriptCore. */
class JavaScriptCoreEngineTest {
    private val engine = JavaScriptCoreEngine()

    @Test
    fun `should let a script read a reset time a person would write`() {
        val run = engine.run(listOf(""), emptyMap(), mapOf("humanDate" to { text -> if (text == "in 2h") 7200.0 else null }),
            "JSON.stringify([humanDate('in 2h'), humanDate('never')])")
        assertEquals(ScriptRun.Value("[7200,null]"), run)
    }

    @Test
    fun `should hand a script its text values`() {
        assertEquals(ScriptRun.Value("hello"), engine.run(emptyList(), mapOf("__input" to "hello"), emptyMap(), "__input"))
    }

    @Test
    fun `should tell a script that fails to load from one that throws or gives nothing`() {
        assertTrue(engine.run(listOf("function ("), emptyMap(), emptyMap(), "1") is ScriptRun.LoadFailed)
        assertTrue(engine.run(emptyList(), emptyMap(), emptyMap(), "read()") is ScriptRun.Threw)
        assertNull((engine.run(emptyList(), emptyMap(), emptyMap(), "undefined") as ScriptRun.Value).text)
    }

    @Test
    fun `should give a mapping script a reset time from what a CLI printed`() {
        val usage = ScriptMapper(
            "r.js",
            "function read(r, c) { return {quotas:[{type:'session',percentRemaining:1,resetsAt:humanDate('resets in 2h')}]}; }",
            engine = engine,
            now = { 1_000.0 },
        ).read(Response("{}"), MappingFacts(), "acme")
        assertEquals(8_200.0, usage.quotas.single().resetsAtSeconds)
    }

    @Test
    fun `should report a script's exception as the reason it couldn't read`() {
        val error = assertFailsWith<UsageError.ParseFailed> {
            ScriptMapper("r.js", "function read() { throw new Error('boom'); }", engine = engine, now = { 0.0 })
                .read(Response("{}"), MappingFacts(), "acme")
        }
        assertEquals("Error: boom", error.reason)
    }
}
