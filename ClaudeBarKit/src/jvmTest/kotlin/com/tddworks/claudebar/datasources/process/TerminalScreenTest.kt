package com.tddworks.claudebar.datasources.process

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.io.File

/**
 * What a TUI's screen shows. The expected text of every case under
 * `resources/terminal-screen/cases` — written by hand, and `fuzz-NNN` drawn at random from
 * the sequences TUIs send — is what SwiftTerm 1.12, the emulator this replaces, rendered for
 * the same bytes at 160×50 with 2000 lines of scrollback, so a mapping reads the same screen.
 */
class TerminalScreenTest {
    private val esc = "\u001b"

    private fun render(raw: String) = TerminalRenderer().render(raw)

    @Test
    fun `should put text where the cursor moves put it`() {
        assertEquals("Hello     World", render("Hello${esc}[5CWorld"))
        assertEquals("Curre t session", render("${esc}[3C${esc}[2BCurre${esc}[10Gt${esc}[12Gsession").trim())
    }

    @Test
    fun `should show only what is left after a line is erased`() {
        assertEquals("ab", render("abcdef${esc}[3G${esc}[0K"))
        assertEquals("def", render("abcdef${esc}[3G${esc}[1K"))
    }

    @Test
    fun `should leave a column for the second half of a wide character`() {
        assertEquals("中 文 abc", render("中文abc"))
    }

    @Test
    fun `should show a space for a character outside the basic plane, as the old terminal did`() {
        assertEquals("a  x", render("a😀x"))
    }

    @Test
    fun `should keep every line that scrolled off the top`() {
        val text = render((0 until 60).joinToString("\n") { "row $it" })
        assertEquals("row 0", text.lines().first())
        assertEquals(60, text.lines().size)
    }

    @Test
    fun `should show the alternate screen while a TUI draws on it, and the normal one after`() {
        assertEquals("alt text", render("normal${esc}[?1049halt text"))
        assertEquals("normal back", render("normal${esc}[?1049halt text${esc}[?1049l back"))
    }

    @Test
    fun `should draw line-drawing characters a TUI selects`() {
        assertEquals("┌──┐\n│  │\n└──┘abc", render("${esc}(0lqqk\nx  x\nmqqj${esc}(Babc"))
    }

    @Test
    fun `should ignore colours, titles and requests a TUI sends`() {
        assertEquals("red plain afterq", render("${esc}[38;5;1mred${esc}[0m plain ${esc}]0;Title\u0007after${esc}[c${esc}[>0qq"))
    }

    @Test
    fun `should wrap a line too long for the screen onto the next row`() {
        assertEquals("a".repeat(160) + "\n" + "a".repeat(10), render("a".repeat(170)))
    }

    @TestFactory
    fun `should show what the old terminal showed for every recorded case`(): List<DynamicTest> {
        val cases = File(resource("terminal-screen/cases")).listFiles().orEmpty().filter { it.name.endsWith(".txt") }.sortedBy { it.name }
        check(cases.size > 90) { "the cases are missing" }
        return cases.map { input ->
            DynamicTest.dynamicTest(input.nameWithoutExtension) {
                val expected = File(resource("terminal-screen/cases-rendered/${input.name}")).readText()
                assertEquals(expected, render(input.readText()))
            }
        }
    }

    private fun resource(path: String): String = requireNotNull(javaClass.classLoader.getResource(path)) { path }.path
}
