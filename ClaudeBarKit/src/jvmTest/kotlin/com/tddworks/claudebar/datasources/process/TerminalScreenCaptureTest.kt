package com.tddworks.claudebar.datasources.process

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File

/**
 * The recorded `/usage` captures (`scripts/claude-usage-captures`), each drawn as the text a
 * mapping reads. The expected text is what SwiftTerm 1.12 rendered for the same capture.
 */
class TerminalScreenCaptureTest {
    private val captures = File("../scripts/claude-usage-captures").listFiles().orEmpty()
        .filter { it.name.endsWith(".txt") }.sortedBy { it.name }

    @TestFactory
    fun `should draw every recorded capture as the old terminal did`(): List<DynamicTest> {
        assertTrue(captures.size >= 50, "the corpus is missing")
        return captures.map { capture ->
            DynamicTest.dynamicTest(capture.name) {
                val expected = File(requireNotNull(javaClass.classLoader.getResource("terminal-screen/captures/${capture.name}")).path).readText()
                assertEquals(expected, TerminalRenderer().render(capture.readText()))
            }
        }
    }

    @TestFactory
    fun `should show the quota bars of every settled capture as rows of text`(): List<DynamicTest> =
        captures.filter { it.name.startsWith("settled") }.map { capture ->
            DynamicTest.dynamicTest(capture.name) {
                val screen = TerminalRenderer().render(capture.readText())
                assertTrue(Regex("""\d+% (used|left)""").containsMatchIn(screen), screen)
            }
        }
}
