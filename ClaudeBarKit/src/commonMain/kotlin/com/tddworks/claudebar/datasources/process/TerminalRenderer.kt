package com.tddworks.claudebar.datasources.process

/**
 * A TUI's captured bytes as the text its screen shows: cursor moves land where they put
 * the text, so a mapping reads rows instead of escape codes (`"screen": "rendered"`).
 */
internal class TerminalRenderer(private val cols: Int = 160, private val rows: Int = 50) {
    /**
     * Scrollback capacity in lines. Output longer than `rows + scrollback` loses its OLDEST
     * lines — for a `/usage` screen the quota sections at the top — so it stays well above
     * the tallest known screen.
     */
    private val scrollback = 2000

    fun render(raw: String): String = TerminalScreen(cols, rows, scrollback).apply { feed(raw) }.text()
}
