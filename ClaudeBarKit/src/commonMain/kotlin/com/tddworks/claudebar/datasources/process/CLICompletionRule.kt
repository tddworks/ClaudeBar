package com.tddworks.claudebar.datasources.process

/**
 * Tells a terminal run when a TUI's screen is actually finished.
 *
 * Going idle is no proof: a CLI may boot for seconds before it opens the screen asked for,
 * then fill it in from a second request (#271, #317). So readiness is decided positively —
 * the screen carries a marker only a settled screen has, the data or the error that replaced
 * it. The capture is cumulative (a redraw appends), so a placeholder proves nothing.
 */
internal data class CLICompletionRule(val readyMarkers: List<Marker>) {
    /**
     * One piece of evidence that the screen has settled. [endsRow] only for a section label
     * the CLI paints as a row of its own: the same words mid-sentence are prose (#317), while
     * a value shares its row (`27% used  Resets 4:59pm`) and must not need the whole row.
     */
    data class Marker(val text: String, val endsRow: Boolean = false) {
        companion object {
            fun row(text: String) = Marker(text, endsRow = true)
        }
    }

    fun isPending(text: String): Boolean = !isReady(text)

    fun isReady(text: String): Boolean {
        val screen = screenText(text)
        return readyMarkers.any { contains(it, screen) }
    }

    /** The markers this text carries, in declared order — what the capture replay reports. */
    fun matchedMarkers(text: String): List<String> {
        val screen = screenText(text)
        return readyMarkers.filter { contains(it, screen) }.map { it.text }
    }

    private companion object {
        /** Padding the terminal painted between two words. */
        const val SEPARATOR = '\u0001'

        /** A real line break, which one label never spans. */
        const val LINE_BREAK = '\u0002'

        /** OSC (…BEL / …ST), CSI, charset designators, and save/restore (`␛7`, `␛8`). */
        val escapeSequence = Regex("\u001B\\][^\u0007\u001B]*(?:\u0007|\u001B\\\\)|\u001B\\[[0-9;?]*[A-Za-z]|\u001B[()][AB012]|\u001B[78]")

        fun isWord(c: Char) = c.isLetter() || c.isDigit() || c.category == CharCategory.LETTER_NUMBER ||
            c.category == CharCategory.OTHER_NUMBER

        /**
         * The text a marker is findable in. Escape sequences become a separator — `Current
         * session` reaches the terminal as `Curre␛[10Gt␛[12Gsession` — and every run of
         * non-word characters collapses to it, so a phrase matches however the CLI split it.
         * A line break stays its own character: two rows never spell one label. As in Swift,
         * where `\r\n` is one character equal to neither, a CRLF pair is padding, and a
         * combining mark belongs to its letter.
         */
        fun screenText(text: String): CharArray {
            val withoutEscapes = escapeSequence.replace(text, SEPARATOR.toString()).lowercase()
            val screen = StringBuilder(withoutEscapes.length)
            var previous: Char? = null
            var i = 0
            while (i < withoutEscapes.length) {
                val character = withoutEscapes[i]
                val crlf = character == '\r' && withoutEscapes.getOrNull(i + 1) == '\n'
                val current = when {
                    crlf -> SEPARATOR
                    character == SEPARATOR -> SEPARATOR
                    isWord(character) || isMark(character) && previous != null && isWord(previous) -> character
                    character == '\n' || character == '\r' -> LINE_BREAK
                    else -> SEPARATOR
                }
                // Any repeat collapses, letters too ("seed" reads "sed") — on both sides alike.
                if (current != previous) screen.append(current)
                previous = current
                i += if (crlf) 2 else 1
            }
            return screen.toString().toCharArray()
        }

        fun isMark(c: Char) = c.category == CharCategory.NON_SPACING_MARK ||
            c.category == CharCategory.COMBINING_SPACING_MARK || c.category == CharCategory.ENCLOSING_MARK

        /**
         * True when [screen] holds [marker], starting a word — a phrase could otherwise match
         * one word's tail and the next one's head — and, for a row marker, ending its row.
         * A marker opening with punctuation (`% used`) brings its own left boundary.
         */
        fun contains(marker: Marker, screen: CharArray): Boolean {
            val needle = screenText(marker.text)
            if (needle.isEmpty() || screen.size < needle.size) return false
            val startsAWord = marker.text.firstOrNull()?.let(::isWord) ?: false
            var start = 0
            while (start <= screen.size - needle.size) {
                if (startsAWord && start > 0 && isWord(screen[start - 1])) {
                    start += 1
                    continue
                }
                val end = match(needle, screen, start)
                if (end != null) {
                    var next = end
                    if (marker.endsRow) {
                        while (next < screen.size && screen[next] == SEPARATOR) next += 1
                    }
                    val atRowEnd = next == screen.size || screen[next] == LINE_BREAK
                    if (marker.endsRow) {
                        if (atRowEnd) return true
                    } else if (atRowEnd || !isWord(screen[next])) {
                        return true
                    }
                }
                start += 1
            }
            return false
        }

        /**
         * Walks [needle] through [screen] from [start]; the index after its last character, or
         * null. Padding is stepped over between the marker's characters, and a separator the
         * marker spells matches one — except a trailing one, left for the boundary check.
         */
        fun match(needle: CharArray, screen: CharArray, start: Int): Int? {
            var index = start
            for ((offset, expected) in needle.withIndex()) {
                val isLast = offset == needle.size - 1
                if (expected == SEPARATOR) {
                    if (index >= screen.size || screen[index] != SEPARATOR) return null
                    if (isLast) break
                    while (index < screen.size && screen[index] == SEPARATOR) index += 1
                    continue
                }
                if (offset > 0) {
                    while (index < screen.size && screen[index] == SEPARATOR) index += 1
                }
                if (index >= screen.size || screen[index] != expected) return null
                index += 1
            }
            return index
        }
    }
}
