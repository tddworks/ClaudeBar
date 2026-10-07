package com.tddworks.claudebar.datasources.process

/**
 * A headless VT100/xterm screen: a TUI's raw bytes in, the text its screen shows out.
 *
 * It replaces SwiftTerm (1.12) and follows it closely enough that every recorded `/usage`
 * capture reads the same (`TerminalScreenCaptureTest`): the VT500 parser table, autowrap
 * with a pending column, scroll regions, the alternate screen, insert mode, tab stops,
 * character sets and SwiftTerm's own quirks, because a mapping was written against them.
 * Colours and other attributes are ignored; nothing is ever answered back to the program.
 */
internal class TerminalScreen(val cols: Int = 160, val rows: Int = 50, val scrollback: Int = 2000) {
    private var normal = newNormalBuffer()
    private val alternate = ScreenBuffer(keepsScrollback = false)
    private var buffer = normal

    private var insertMode = false
    private var wraparound = true
    private var originMode = false
    private var reverseWraparound = false
    /** `convertEol`: a line feed also returns to the first column. */
    private var lineFeedMode = true
    private var charset: Map<Int, String>? = null
    private val gCharsets = arrayOfNulls<Map<Int, String>>(4)
    private var gLevel = 0

    private val parser = Parser()

    /**
     * Only the buffer active at start-up gets its right margin, as in SwiftTerm: the alternate
     * screen keeps 0, so there a line feed scrolls only from the first column.
     */
    private fun newNormalBuffer() = ScreenBuffer(keepsScrollback = true).also {
        it.fillViewportRows()
        it.marginRight = cols - 1
    }

    fun feed(text: String) = feed(text.encodeToByteArray())

    fun feed(bytes: ByteArray) = parser.parse(bytes)

    /**
     * Every line kept, oldest first — scrollback, then the screen — read as SwiftTerm's
     * renderer read it: a cell holding one UTF-16 unit shows it, any other cell (empty, the
     * second half of a wide character, a character outside the BMP or a joined cluster)
     * shows a space; each line trimmed of spaces at both ends, empty lines dropped from the end.
     */
    fun text(): String {
        val lines = ArrayList<String>()
        for (row in 0 until rows + scrollback) {
            val line = buffer.scrollInvariantLine(row) ?: continue
            val text = StringBuilder(cols)
            for (col in 0 until cols) {
                val glyph = line.glyphs[col]
                text.append(if (glyph != null && glyph.length == 1 && glyph[0] != '\u0000') glyph[0] else ' ')
            }
            lines += text.toString().trim(' ', '\t', '\u0000')
        }
        return lines.dropLastWhile { it.isEmpty() }.joinToString("\n")
    }

    // region Cells and buffers

    /** One row: each cell's text (null when empty) and the columns it takes (0 for a wide character's second half). */
    private inner class ScreenLine {
        val glyphs = arrayOfNulls<String>(cols)
        val widths = ByteArray(cols) { 1 }
        var isWrapped = false

        fun set(col: Int, glyph: String?, width: Int) {
            glyphs[col] = glyph
            widths[col] = width.toByte()
        }

        fun copyCell(to: Int, from: Int) = set(to, glyphs[from], widths[from].toInt())

        fun copyCell(to: Int, source: ScreenLine, from: Int) = set(to, source.glyphs[from], source.widths[from].toInt())

        fun clear(from: Int = 0, until: Int = cols) {
            for (col in from until minOf(until, cols)) set(col, null, 1)
        }

        /** Inserts [n] blanks at [at], pushing the rest right and off the edge. */
        fun insertCells(at: Int, n: Int) {
            val length = cols
            val pos = at % length
            if (n < length - pos) {
                for (i in (0 until length - pos - n).reversed()) copyCell(pos + n + i, pos + i)
                for (i in 0 until n) set(pos + i, null, 1)
            } else {
                clear(pos, length)
            }
        }

        /** Deletes [n] cells at [at], pulling the rest left and blanking the right edge. */
        fun deleteCells(at: Int, n: Int) {
            val length = cols
            val p = at % length
            if (n < length - p) {
                for (i in 0 until length - at - n) copyCell(at + i, at + n + i)
                for (i in length - n until length) set(i, null, 1)
            } else {
                clear(at, length)
            }
        }
    }

    /** Where the last character went, so a combining one that follows can join it. */
    private class LastPoke(val line: Int, val col: Int, val cols: Int, val rows: Int)

    /** The normal screen with its scrollback, or the alternate one without. */
    private inner class ScreenBuffer(val keepsScrollback: Boolean) {
        val maxLength = if (keepsScrollback) scrollback + rows else rows
        val lines = ArrayDeque<ScreenLine>()
        /** How many lines fell off the top of a full scrollback — the first line's scroll-invariant row. */
        var linesTop = 0
        var yBase = 0
        var x = 0
        var y = 0
        var scrollTop = 0
        var scrollBottom = rows - 1
        /** Left and right margins, used without DECLRMM too: a line feed scrolls only inside them. */
        val marginLeft = 0
        var marginRight = 0
        var savedX = 0
        var savedY = 0
        var savedCharset: Map<Int, String>? = null
        var savedWraparound = false
        var savedOriginMode = false
        var savedReverseWraparound = false
        /**
         * Every 8 columns — but SwiftTerm makes its buffers 80 columns wide before it resizes
         * them, so at start-up only the first 80 have stops; after a reset (RIS) all do.
         */
        var tabStops = BooleanArray(cols).also { stops -> for (i in 0 until minOf(cols, 80) step 8) stops[i] = true }
        var last = LastPoke(0, 0, 0, 0)

        fun fillViewportRows() {
            if (lines.isNotEmpty()) return
            repeat(rows) { lines.addLast(ScreenLine()) }
        }

        fun clear() {
            yBase = 0
            linesTop = 0
            x = 0
            y = 0
            lines.clear()
        }

        fun line(row: Int): ScreenLine = lines[yBase + row]

        fun scrollInvariantLine(row: Int): ScreenLine? =
            if (row < linesTop || row >= lines.size + linesTop) null else lines[row - linesTop]

        /** Inserts [line] at [index], dropping the oldest line when the buffer is full. */
        fun insertTrimming(index: Int, line: ScreenLine) {
            lines.add(minOf(index, lines.size), line)
            if (lines.size > maxLength) lines.removeFirst()
        }

        fun nextTabStop(from: Int = x): Int {
            val limit = cols - 1
            var index = from
            do {
                index += 1
                if (index > limit) break
                if (tabStops[index]) break
            } while (index < limit)
            return if (index >= limit) limit else index
        }

        fun previousTabStop(from: Int = x): Int {
            var index = from
            while (index > 0 && !tabStops[index - 1]) index -= 1
            if (index > 0) index -= 1
            return if (index >= cols) cols - 1 else index
        }

        fun softReset() {
            marginRight = cols - 1
            savedY = 0
            savedX = 0
            savedCharset = null
            savedWraparound = false
            savedOriginMode = false
            savedReverseWraparound = false
        }
    }

    // endregion

    // region Printing

    /** A print run's bytes, decoded as SwiftTerm's reading buffer does: a partial sequence waits for more. */
    private var putback = ByteArray(0)

    private fun handlePrint(data: ByteArray, from: Int, until: Int) {
        if (charset == null && putback.isEmpty()) {
            var allAscii = true
            for (i in from until until) if (data[i] < 0) { allAscii = false; break }
            if (allAscii) {
                val consumed = insertAsciiRun(data, from, until)
                if (consumed == until - from) return
            }
        }
        val bytes = putback + data.copyOfRange(from, until)
        putback = ByteArray(0)
        var i = 0
        while (i < bytes.size) {
            val code = bytes[i].toInt() and 0xFF
            i += 1
            val n = expectedSize(code)
            if (n == -1 || n == 1) {
                val mapped = if (code < 127) charset?.get(code) else null
                if (mapped != null) {
                    insert(mapped.substring(0, minOf(mapped.length, charLength(mapped))), 1)
                    continue
                }
                val width = TerminalGlyphs.columnWidth(code)
                if (width > 0) insert(TerminalGlyphs.string(code), width)
                continue
            }
            if (bytes.size - i < n - 1) {
                putback = bytes.copyOfRange(i - 1, bytes.size)
                return
            }
            val sequence = bytes.copyOfRange(i - 1, i - 1 + n)
            i += n - 1
            val scalar = decodeUtf8(sequence)
            if (scalar == null) {
                val width = TerminalGlyphs.columnWidth(code)
                if (width > 0) insert(TerminalGlyphs.string(code), width)
                continue
            }
            printScalar(scalar)
        }
    }

    private fun charLength(text: String) = if (text.isNotEmpty() && text[0].isHighSurrogate()) 2 else 1

    /** A decoded character: joined to the one before it when it combines, else placed in the next cell. */
    private fun printScalar(scalar: Int) {
        val width = TerminalGlyphs.columnWidth(scalar)
        if (width < 0) return
        var tryJoin = width == 0 || TerminalGlyphs.isMark(scalar) || TerminalGlyphs.isEmojiModifier(scalar) ||
            TerminalGlyphs.isVariationSelector(scalar) || scalar == TerminalGlyphs.ZERO_WIDTH_JOINER
        val last = buffer.last
        val lastIsHere = last.cols == cols && last.rows == rows && last.line < buffer.lines.size
        if (!tryJoin && lastIsHere) {
            val previous = buffer.lines[last.line].glyphs[minOf(last.col, cols - 1)] ?: "\u0000"
            val points = TerminalGlyphs.codePoints(previous)
            if (points.lastOrNull() == TerminalGlyphs.ZERO_WIDTH_JOINER) {
                tryJoin = true
            } else if (TerminalGlyphs.isRegionalIndicator(scalar) && points.size == 1 && TerminalGlyphs.isRegionalIndicator(points[0])) {
                tryJoin = true
            }
        }
        if (tryJoin && lastIsHere && joinPrevious(scalar, last)) return
        if (width == 0) return
        insert(TerminalGlyphs.string(scalar), width)
    }

    /** True when [scalar] joined the last cell written — or was dropped as a selector with nothing to select. */
    private fun joinPrevious(scalar: Int, last: LastPoke): Boolean {
        val line = buffer.lines[last.line]
        val col = if (last.col >= cols) cols - 1 else last.col
        val previous = line.glyphs[col] ?: "\u0000"
        if (!TerminalGlyphs.joins(previous, scalar)) return false
        val joined = previous + TerminalGlyphs.string(scalar)
        val oldWidth = line.widths[col].toInt()
        val isVs16 = scalar == 0xFE0F
        val isVs15 = scalar == 0xFE0E
        if (isVs16 || isVs15) {
            val base = TerminalGlyphs.codePoints(previous).lastOrNull()
            if (base == null || !TerminalGlyphs.isEmojiVs16Base(base)) return true
        }
        when {
            isVs16 -> if (oldWidth != 2 && col + 1 < cols) {
                line.set(col, joined, 2)
                line.set(col + 1, null, 0)
                buffer.x += 1
            } else {
                line.set(col, joined, oldWidth)
            }
            isVs15 -> {
                line.set(col, joined, 1)
                if (oldWidth == 2 && buffer.x > 0) buffer.x -= 1
            }
            else -> line.set(col, joined, oldWidth)
        }
        return true
    }

    /** ASCII written straight into cells, a line at a time; returns the bytes it placed. */
    private fun insertAsciiRun(data: ByteArray, from: Int, until: Int): Int {
        if (insertMode) return 0
        val b = buffer
        val right = cols - 1
        var consumed = 0
        var index = from
        while (index < until) {
            if (b.x > right) {
                if (!wraparound) break
                b.x = 0
                if (b.y >= b.scrollBottom) {
                    scroll(isWrapped = true)
                } else {
                    b.y += 1
                    b.line(b.y).isWrapped = true
                }
            }
            val run = minOf(right - b.x + 1, until - index)
            val line = b.line(b.y)
            for (i in 0 until run) line.set(b.x + i, ASCII[data[index + i].toInt()], 1)
            b.x += run
            consumed += run
            index += run
        }
        if (consumed > 0) b.last = LastPoke(b.y + b.yBase, b.x - 1, cols, rows)
        return consumed
    }

    /** Puts one character in the next cell, wrapping, scrolling and shifting (insert mode) as the terminal does. */
    private fun insert(glyph: String?, width: Int) {
        val b = buffer
        var remaining = width
        val right = cols - 1
        if (b.x + width - 1 > right) {
            if (wraparound) {
                b.x = 0
                if (b.y >= b.scrollBottom) {
                    scroll(isWrapped = true)
                } else {
                    b.y += 1
                    b.line(b.y).isWrapped = true
                }
            } else {
                if (width == 2) return
                b.x = right
            }
        }
        val line = b.line(b.y)
        if (insertMode) {
            line.insertCells(b.x, width)
            if (line.widths[cols - 1].toInt() == 2) line.set(cols - 1, null, 1)
        }
        b.last = LastPoke(b.y + b.yBase, b.x, cols, rows)
        if (b.x >= cols) b.x = cols - 1
        line.set(b.x, glyph, width)
        b.x += 1
        if (remaining > 1) {
            remaining -= 1
            while (remaining != 0 && b.x < cols) {
                line.set(b.x, null, 0)
                b.x += 1
                remaining -= 1
            }
        }
    }

    // endregion

    // region Scrolling

    private fun scroll(isWrapped: Boolean = false) {
        val b = buffer
        val newLine = ScreenLine().also { it.isWrapped = isWrapped }
        val topRow = b.yBase + b.scrollTop
        val bottomRow = b.yBase + b.scrollBottom
        if (b.scrollTop == 0) {
            val willTrim = b.lines.size == b.maxLength
            b.insertTrimming(bottomRow + 1, newLine)
            if (!willTrim) b.yBase += 1 else if (b.keepsScrollback) b.linesTop += 1
        } else {
            if (bottomRow >= b.lines.size) return
            for (row in topRow until bottomRow) b.lines[row] = b.lines[row + 1]
            b.lines[bottomRow] = newLine
        }
    }

    private fun canScroll() = buffer.x >= buffer.marginLeft && buffer.x <= buffer.marginRight

    private fun lineFeed() {
        val b = buffer
        if (b.y == b.scrollBottom) {
            if (canScroll()) scroll()
        } else if (b.y != rows - 1) {
            b.y += 1
        }
        if (b.x >= cols) b.x -= 1
        if (lineFeedMode) b.x = 0
    }

    private fun index() {
        restrictPosition()
        val b = buffer
        val newY = b.y + 1
        if (newY > b.scrollBottom) {
            if (canScroll()) scroll()
        } else {
            b.y = newY
        }
        if (b.x > cols) b.x -= 1
    }

    private fun reverseIndex() {
        val b = buffer
        restrictPosition()
        if (b.y == b.scrollTop) {
            if (!canScroll()) return
            val topRow = b.yBase + b.scrollTop
            if (topRow >= b.lines.size) return
            val height = b.scrollBottom - b.scrollTop
            for (i in (0 until height).reversed()) {
                if (topRow + i + 1 < b.lines.size) b.lines[topRow + i + 1] = b.lines[topRow + i]
            }
            b.lines[topRow] = ScreenLine()
        } else if (b.y > 0) {
            b.y -= 1
        }
    }

    // endregion

    // region Positions

    private fun restrictPosition(limitCols: Boolean = true) {
        val b = buffer
        b.x = minOf(cols - if (limitCols) 1 else 0, maxOf(0, b.x))
        b.y = if (originMode) minOf(b.scrollBottom, maxOf(b.scrollTop, b.y)) else minOf(rows - 1, maxOf(0, b.y))
    }

    private fun setPosition(col: Int, row: Int) {
        val b = buffer
        if (originMode) {
            b.x = col
            b.y = b.scrollTop + row
        } else {
            b.x = col
            b.y = row
        }
        restrictPosition()
    }

    private fun backspace() {
        val b = buffer
        restrictPosition(!reverseWraparound)
        if (b.x > 0) {
            b.x -= 1
        } else if (reverseWraparound) {
            if (b.y > b.scrollTop && b.y <= b.scrollBottom && b.line(b.y).isWrapped) {
                b.line(b.y).isWrapped = false
                b.y -= 1
                b.x = cols - 1
            } else if (b.y == b.scrollTop) {
                b.x = cols - 1
                b.y = b.scrollBottom
            } else if (b.y > 0) {
                b.x = cols - 1
                b.y -= 1
            }
        }
    }

    private fun up(pars: List<Int>) {
        val b = buffer
        val count = maxOf(pars[0], 1)
        val top = if (b.y < b.scrollTop) 0 else b.scrollTop
        b.y = if (b.y - count < top) top else b.y - count
    }

    private fun down(pars: List<Int>) {
        val b = buffer
        val count = maxOf(pars[0], 1)
        val bottom = if (b.y > b.scrollBottom) rows - 1 else b.scrollBottom
        val newY = b.y + count
        b.y = if (newY >= bottom) bottom else newY
        if (b.x >= cols) b.x -= 1
    }

    private fun forward(count: Int) {
        val b = buffer
        b.x += maxOf(count, 1)
        if (b.x > cols - 1) b.x = cols - 1
    }

    private fun backward(count: Int) {
        val b = buffer
        val newX = b.x - maxOf(1, count)
        b.x = if (newX < 0) 0 else newX
    }

    private fun saveState() {
        val b = buffer
        b.savedX = b.x
        b.savedY = b.y
        b.savedCharset = charset
        b.savedWraparound = wraparound
        b.savedOriginMode = originMode
        b.savedReverseWraparound = reverseWraparound
    }

    private fun restoreState() {
        val b = buffer
        b.x = minOf(maxOf(0, b.savedX), cols - 1)
        b.y = minOf(maxOf(0, b.savedY), rows - 1)
        charset = b.savedCharset
        originMode = b.savedOriginMode
        wraparound = b.savedWraparound
        reverseWraparound = b.savedReverseWraparound
    }

    // endregion

    // region Erasing and editing

    private fun eraseInLine(mode: Int) {
        val b = buffer
        val line = b.line(b.y)
        when (mode) {
            0 -> line.clear(b.x, cols)
            1 -> line.clear(0, b.x + 1)
            2 -> line.clear(0, cols)
        }
    }

    private fun eraseInDisplay(mode: Int) {
        val b = buffer
        when (mode) {
            0 -> {
                b.line(b.y).clear(b.x, cols)
                if (b.x == 0) b.line(b.y).isWrapped = false
                for (row in b.y + 1 until rows) resetLine(row)
            }
            1 -> {
                b.line(b.y).clear(0, b.x + 1)
                b.line(b.y).isWrapped = false
                for (row in b.y - 1 downTo 0) resetLine(row)
            }
            2 -> for (row in rows - 1 downTo 0) resetLine(row)
            3 -> {
                val scrollbackSize = b.lines.size - rows
                if (scrollbackSize > 0) {
                    repeat(scrollbackSize) { b.lines.removeFirst() }
                    b.linesTop = 0
                    b.yBase = maxOf(b.yBase - scrollbackSize, 0)
                }
            }
        }
    }

    private fun resetLine(row: Int) {
        val line = buffer.line(row)
        line.clear()
        line.isWrapped = false
    }

    private fun insertLines(pars: List<Int>) {
        val b = buffer
        if (b.y < b.scrollTop || b.y > b.scrollBottom) return
        val count = minOf(b.maxLength * 2, maxOf(pars[0], 1))
        val row = b.y + b.yBase
        val bottom = b.yBase + b.scrollBottom
        repeat(count) {
            b.lines.removeAt(bottom)
            b.lines.add(row, ScreenLine())
        }
    }

    private fun deleteLines(pars: List<Int>) {
        restrictPosition()
        val b = buffer
        val count = minOf(rows + 1, maxOf(pars[0], 1))
        val row = b.y + b.yBase
        val bottom = b.yBase + b.scrollBottom
        if (b.y < b.scrollTop || b.y > b.scrollBottom) return
        repeat(count) {
            b.lines.removeAt(row)
            b.lines.add(bottom, ScreenLine())
        }
    }

    private fun scrollUp(pars: List<Int>) {
        val b = buffer
        repeat(minOf(rows * 2, maxOf(pars[0], 1))) {
            b.lines.removeAt(b.yBase + b.scrollTop)
            b.lines.add(b.yBase + b.scrollBottom, ScreenLine())
        }
    }

    private fun scrollDown(pars: List<Int>) {
        val b = buffer
        val row = b.scrollTop + b.yBase
        val height = b.scrollBottom - b.scrollTop
        val columns = b.marginLeft..b.marginRight
        repeat(minOf(maxOf(pars[0], 1), rows)) {
            for (i in (0 until height).reversed()) {
                for (col in columns) b.lines[row + i + 1].copyCell(col, b.lines[row + i], col)
            }
            b.lines[row].clear(b.marginLeft, b.marginRight + 1)
        }
    }

    private fun deleteChars(pars: List<Int>) {
        val b = buffer
        if (b.x == cols) return
        b.line(b.y).deleteCells(b.x, maxOf(pars[0], 1))
    }

    private fun repeatPreceding(pars: List<Int>) {
        val b = buffer
        val count = minOf(cols * rows * 2, maxOf(pars[0], 1))
        val line = b.line(b.y)
        val glyph = if (b.x - 1 < 0) null else line.glyphs[b.x - 1]
        val width = if (b.x - 1 < 0) 1 else line.widths[b.x - 1].toInt()
        repeat(count) { insert(glyph, width) }
    }

    /** DECBI / DECFI at a margin: the scroll region's columns move instead of the cursor. */
    private fun columnScroll(back: Boolean, at: Int) {
        val b = buffer
        if (b.y < b.scrollTop || b.y > b.scrollBottom || b.x < b.marginLeft || b.x > b.marginRight) return
        for (row in b.scrollTop..b.scrollBottom) {
            val line = b.line(row)
            if (back) line.insertCells(at, 1) else line.deleteCells(at, 1)
        }
    }

    private fun alignmentPattern() {
        setPosition(0, 0)
        val b = buffer
        for (offset in 0 until rows) {
            val line = b.lines[b.y + b.yBase + offset]
            for (col in 0 until cols) line.set(col, "E", 1)
            line.isWrapped = false
        }
        setPosition(0, 0)
    }

    // endregion

    // region Modes and resets

    private fun setMode(par: Int, collect: String) {
        if (collect.isEmpty()) {
            when (par) {
                4 -> insertMode = true
                20 -> lineFeedMode = true
            }
        } else if (collect == "?") {
            when (par) {
                2 -> { for (i in 0..3) setCharset(i, null) }
                // DECCOLM resizes to 132 columns and resets; a fixed-size screen only resets.
                3 -> resetToInitialState()
                6 -> originMode = true
                7 -> wraparound = true
                45 -> if (wraparound) reverseWraparound = true
                1048 -> saveState()
                1049, 47, 1047 -> {
                    if (par == 1049) saveState()
                    activateAlternate()
                }
            }
        }
    }

    private fun resetMode(par: Int, collect: String) {
        if (collect.isEmpty()) {
            when (par) {
                4 -> insertMode = false
                20 -> lineFeedMode = false
            }
        } else if (collect == "?") {
            when (par) {
                3 -> resetToInitialState()
                6 -> originMode = false
                7 -> wraparound = false
                45 -> reverseWraparound = false
                1048 -> restoreState()
                1049, 47, 1047 -> {
                    activateNormal(clearAlternate = par == 1047 || par == 1049)
                    if (par == 1049) restoreState()
                }
            }
        }
    }

    private fun activateAlternate() {
        if (buffer === alternate) return
        alternate.x = normal.x
        alternate.y = normal.y
        alternate.fillViewportRows()
        buffer = alternate
    }

    private fun activateNormal(clearAlternate: Boolean) {
        if (buffer === normal) return
        normal.x = alternate.x
        normal.y = alternate.y
        if (clearAlternate) alternate.clear()
        buffer = normal
    }

    private fun softReset() {
        insertMode = false
        originMode = false
        reverseWraparound = false
        wraparound = true
        buffer.scrollTop = 0
        buffer.scrollBottom = rows - 1
        buffer.softReset()
        charset = null
        setLevel(0)
        lineFeedMode = true
    }

    private fun resetToInitialState() {
        normal = ScreenBuffer(keepsScrollback = true).also {
            it.fillViewportRows()
            it.tabStops = BooleanArray(cols).also { stops -> for (i in 0 until cols step 8) stops[i] = true }
        }
        activateNormal(clearAlternate = false)
        buffer = normal
        buffer.marginRight = cols - 1
        originMode = false
        insertMode = false
        wraparound = true
        for (i in 0..3) gCharsets[i] = null
        charset = null
        gLevel = 0
        buffer.scrollTop = 0
        buffer.scrollBottom = rows - 1
        lineFeedMode = true
    }

    private fun setLevel(level: Int) {
        gLevel = level
        charset = if (level < gCharsets.size) gCharsets[level] else null
    }

    private fun setCharset(index: Int, set: Map<Int, String>?) {
        if (index >= gCharsets.size) return
        gCharsets[index] = set
        if (gLevel == index) charset = set
    }

    private fun selectCharset(prefix: Char, designator: Char) {
        val set = TerminalCharsets.all[designator]
        val index = when (prefix) {
            '(' -> 0
            ')', '-' -> 1
            '*', '.' -> 2
            '+', '/' -> 3
            else -> return
        }
        setCharset(index, set)
    }

    private fun setScrollRegion(pars: List<Int>, collect: String) {
        if (collect.isNotEmpty()) return
        val b = buffer
        val top = if (pars.isNotEmpty()) maxOf(pars[0] - 1, 0) else 0
        var bottom = rows
        if (pars.size > 1 && pars[1] != 0) bottom = minOf(pars[1], rows)
        bottom -= 1
        if (top < bottom) {
            b.scrollBottom = bottom
            b.scrollTop = top
        }
        setPosition(0, 0)
    }

    // endregion

    // region Dispatch

    private fun execute(code: Int) {
        when (code) {
            8 -> backspace()
            9 -> buffer.x = buffer.nextTabStop()
            10 -> lineFeed()
            11, 12 -> lineFeed()
            13 -> buffer.x = 0
            14 -> setLevel(1)
            15 -> setLevel(0)
            0x84 -> index()
            0x85 -> { buffer.x = 0; index() }
            0x88 -> tabSet()
        }
    }

    private fun tabSet() {
        val b = buffer
        if (b.x < b.tabStops.size) b.tabStops[b.x] = true
    }

    private fun dispatchCsi(final: Int, pars: List<Int>, collect: String) {
        val b = buffer
        when (final.toChar()) {
            '@' -> b.line(b.y).insertCells(b.x, maxOf(pars[0], 1))
            'A' -> up(pars)
            'B' -> down(pars)
            'C' -> forward(pars[0])
            'D' -> backward(pars[0])
            'E' -> { down(pars); b.x = 0 }
            'F' -> { up(pars); b.x = 0 }
            'G' -> b.x = minOf(maxOf(pars[0], 1) - 1, cols - 1)
            'H' -> setPosition(if (pars.size >= 2) maxOf(1, pars[1]) - 1 else 0, maxOf(1, pars[0]) - 1)
            'I' -> repeat(minOf(cols - 1, maxOf(pars[0], 1))) { b.x = b.nextTabStop() }
            'J' -> eraseInDisplay(pars[0])
            'K' -> eraseInLine(pars[0])
            'L' -> insertLines(pars)
            'M' -> deleteLines(pars)
            'P' -> deleteChars(pars)
            'S' -> scrollUp(pars)
            'T' -> if (collect.isEmpty()) scrollDown(pars)
            'X' -> b.line(b.y).clear(b.x, b.x + maxOf(pars[0], 1))
            'Z' -> if (b.x <= cols) repeat(minOf(cols, maxOf(pars[0], 1))) { b.x = b.previousTabStop() }
            '`' -> b.x = minOf(maxOf(pars[0], 1) - 1, cols - 1)
            'a' -> b.x = minOf(b.x + maxOf(pars[0], 1), cols - 1)
            'b' -> repeatPreceding(pars)
            'd' -> b.y = minOf(maxOf(pars[0], 1) - 1, rows - 1)
            'e' -> {
                b.y = minOf(b.y + maxOf(pars[0], 1), rows - 1)
                if (b.x >= cols) b.x -= 1
            }
            'f' -> {
                val row = maxOf(pars[0], 1)
                val col = if (pars.size > 1) maxOf(pars[1], 1) else 1
                b.y = minOf(row - 1 + if (originMode) b.scrollTop else 0, rows - 1)
                b.x = minOf(col - 1, cols - 1)
            }
            'g' -> when (pars[0]) {
                0 -> if (b.x < b.tabStops.size) b.tabStops[b.x] = false
                3 -> b.tabStops = BooleanArray(cols)
            }
            'h' -> pars.forEach { setMode(it, collect) }
            'l' -> pars.forEach { resetMode(it, collect) }
            'p' -> if (collect == "!") softReset()
            'r' -> setScrollRegion(pars, collect)
            's' -> saveState()
            'u' -> if (collect.isEmpty()) restoreState()
            else -> Unit
        }
    }

    private fun dispatchEsc(collect: String, final: Int) {
        val c = final.toChar()
        if (collect.isEmpty()) {
            when (c) {
                '6' -> if (buffer.x == buffer.marginLeft) columnScroll(back = true, at = buffer.x) else backward(1)
                '7' -> saveState()
                '8' -> restoreState()
                '9' -> when (buffer.x) {
                    buffer.marginRight -> columnScroll(back = false, at = buffer.marginLeft)
                    cols -> Unit
                    else -> forward(1)
                }
                'D' -> index()
                'E' -> { buffer.x = 0; index() }
                'H' -> tabSet()
                'M' -> reverseIndex()
                'c' -> resetToInitialState()
                'n' -> setLevel(2)
                'o', '|' -> setLevel(3)
                '}' -> setLevel(2)
                '~' -> setLevel(1)
            }
        } else if (collect.length == 1) {
            val prefix = collect[0]
            when (prefix) {
                '%' -> if (c == '@' || c == 'G') { setLevel(0); setCharset(0, null) }
                '#' -> if (c == '8') alignmentPattern()
                '(', ')', '*', '+', '-', '.', '/' -> if (TerminalCharsets.all.containsKey(c)) selectCharset(prefix, c)
            }
        }
    }

    // endregion

    /** SwiftTerm's VT500 parser: its transition table, its print runs, its error path for bytes above 0x9F. */
    private inner class Parser {
        private var state = GROUND
        private var collect = StringBuilder()
        private var pars = mutableListOf(0)

        fun parse(data: ByteArray) {
            var print = -1
            var i = 0
            val end = data.size
            while (i < end) {
                val code = data[i].toInt() and 0xFF
                if (state == GROUND && code > 0x1F) {
                    if (print == -1) print = i
                    do { i += 1 } while (i < end && (data[i].toInt() and 0xFF) > 0x1F)
                    continue
                }
                if (state == CSI_PARAM && code in 0x30..0x39) {
                    pars[pars.size - 1] = digit(pars[pars.size - 1], code)
                    i += 1
                    continue
                }
                var transition = TABLE[(state shl 8) or (if (code < 0xA0) code else 0xA0)]
                when (transition shr 4) {
                    PRINT -> if (print == -1) print = i
                    EXECUTE -> {
                        if (print != -1) { handlePrint(data, print, i); print = -1 }
                        execute(code)
                    }
                    IGNORE -> if (print != -1) { handlePrint(data, print, i); print = -1 }
                    ERROR -> if (code > 0x9F) {
                        when (state) {
                            GROUND -> if (print == -1) print = i
                            CSI_IGNORE -> transition = transition or CSI_IGNORE
                            DCS_IGNORE -> transition = transition or DCS_IGNORE
                            DCS_PASSTHROUGH -> transition = transition or DCS_PASSTHROUGH
                        }
                    }
                    CSI_DISPATCH -> dispatchCsi(code, pars, collect.toString())
                    PARAM -> if (code == 0x3B || code == 0x3A) pars.add(0) else pars[pars.size - 1] = digit(pars[pars.size - 1], code)
                    ESC_DISPATCH -> dispatchEsc(collect.toString(), code)
                    COLLECT -> collect.append(code.toChar())
                    CLEAR -> {
                        if (print != -1) { handlePrint(data, print, i); print = -1 }
                        reset()
                    }
                    DCS_HOOK, DCS_PUT -> Unit
                    DCS_UNHOOK, OSC_END -> {
                        if (code == 0x1B) transition = transition or ESCAPE
                        reset()
                    }
                    OSC_START -> if (print != -1) { handlePrint(data, print, i); print = -1 }
                    OSC_PUT -> {
                        var j = i
                        while (j < end) {
                            val c = data[j].toInt() and 0xFF
                            if (c == 0x07 || c == 0x18 || c == 0x1B) break
                            j += 1
                        }
                        i = j - 1
                    }
                }
                state = transition and 15
                i += 1
            }
            if (state == GROUND && print != -1) handlePrint(data, print, end)
        }

        private fun reset() {
            pars = mutableListOf(0)
            collect = StringBuilder()
            putback = ByteArray(0)
        }

        private fun digit(value: Int, code: Int): Int {
            val next = value.toLong() * 10 + (code - 48)
            return if (next > Int.MAX_VALUE / 10 - 10) 0 else next.toInt()
        }
    }

    private companion object {
        const val GROUND = 0
        const val ESCAPE = 1
        const val ESCAPE_INTERMEDIATE = 2
        const val CSI_ENTRY = 3
        const val CSI_PARAM = 4
        const val CSI_INTERMEDIATE = 5
        const val CSI_IGNORE = 6
        const val SOS_PM_APC_STRING = 7
        const val OSC_STRING = 8
        const val APC_STRING = 9
        const val DCS_ENTRY = 10
        const val DCS_PARAM = 11
        const val DCS_IGNORE = 12
        const val DCS_INTERMEDIATE = 13
        const val DCS_PASSTHROUGH = 14

        const val IGNORE = 0
        const val ERROR = 1
        const val PRINT = 2
        const val EXECUTE = 3
        const val OSC_START = 4
        const val OSC_PUT = 5
        const val OSC_END = 6
        const val CSI_DISPATCH = 7
        const val PARAM = 8
        const val COLLECT = 9
        const val ESC_DISPATCH = 10
        const val CLEAR = 11
        const val DCS_HOOK = 12
        const val DCS_PUT = 13
        const val DCS_UNHOOK = 14

        /** `(state << 8) | code` → `(action << 4) | next`, built in SwiftTerm's order: later rules win. */
        val TABLE: IntArray = IntArray(16 * 256).also { table ->
            fun add(code: Int, state: Int, action: Int, next: Int) { table[(state shl 8) or code] = (action shl 4) or next }
            fun add(codes: Iterable<Int>, state: Int, action: Int, next: Int) = codes.forEach { add(it, state, action, next) }
            fun r(low: Int, high: Int) = low until high
            val states = GROUND..DCS_PASSTHROUGH
            for (state in states) for (code in 0..0xA0) add(code, state, ERROR, GROUND)
            val printables = r(0x20, 0x7F)
            val executables = r(0x00, 0x19) + r(0x1C, 0x20)
            add(printables, GROUND, PRINT, GROUND)
            for (state in states) {
                add(listOf(0x18, 0x1A, 0x99, 0x9A), state, EXECUTE, GROUND)
                add(r(0x80, 0x90), state, EXECUTE, GROUND)
                add(r(0x90, 0x98), state, EXECUTE, GROUND)
                add(0x9C, state, IGNORE, GROUND)
                add(0x1B, state, CLEAR, ESCAPE)
                add(0x9D, state, OSC_START, OSC_STRING)
                add(listOf(0x98, 0x9E), state, IGNORE, SOS_PM_APC_STRING)
                add(0x9F, state, OSC_START, APC_STRING)
                add(0x9B, state, CLEAR, CSI_ENTRY)
                add(0x90, state, CLEAR, DCS_ENTRY)
            }
            add(executables, GROUND, EXECUTE, GROUND)
            add(executables, ESCAPE, EXECUTE, ESCAPE)
            add(0x7F, ESCAPE, IGNORE, ESCAPE)
            add(executables, OSC_STRING, IGNORE, OSC_STRING)
            add(executables, APC_STRING, IGNORE, APC_STRING)
            add(executables, CSI_ENTRY, EXECUTE, CSI_ENTRY)
            add(0x7F, CSI_ENTRY, IGNORE, CSI_ENTRY)
            add(executables, CSI_PARAM, EXECUTE, CSI_PARAM)
            add(0x7F, CSI_PARAM, IGNORE, CSI_PARAM)
            add(executables, CSI_IGNORE, EXECUTE, CSI_IGNORE)
            add(executables, CSI_INTERMEDIATE, EXECUTE, CSI_INTERMEDIATE)
            add(0x7F, CSI_INTERMEDIATE, IGNORE, CSI_INTERMEDIATE)
            add(executables, ESCAPE_INTERMEDIATE, EXECUTE, ESCAPE_INTERMEDIATE)
            add(0x7F, ESCAPE_INTERMEDIATE, IGNORE, ESCAPE_INTERMEDIATE)
            add(0x5D, ESCAPE, OSC_START, OSC_STRING)
            add(printables, OSC_STRING, OSC_PUT, OSC_STRING)
            add(0x7F, OSC_STRING, OSC_PUT, OSC_STRING)
            add(listOf(0x9C, 0x1B, 0x18, 0x1A, 0x07), OSC_STRING, OSC_END, GROUND)
            add(r(0x1C, 0x20), OSC_STRING, IGNORE, OSC_STRING)
            add(0x5F, ESCAPE, OSC_START, APC_STRING)
            add(printables, APC_STRING, OSC_PUT, APC_STRING)
            add(0x7F, APC_STRING, OSC_PUT, APC_STRING)
            add(listOf(0x9C, 0x1B, 0x18, 0x1A, 0x07), APC_STRING, OSC_END, GROUND)
            add(r(0x1C, 0x20), APC_STRING, IGNORE, APC_STRING)
            add(listOf(0x58, 0x5E), ESCAPE, IGNORE, SOS_PM_APC_STRING)
            add(printables, SOS_PM_APC_STRING, IGNORE, SOS_PM_APC_STRING)
            add(executables, SOS_PM_APC_STRING, IGNORE, SOS_PM_APC_STRING)
            add(0x9C, SOS_PM_APC_STRING, IGNORE, GROUND)
            add(0x7F, SOS_PM_APC_STRING, IGNORE, SOS_PM_APC_STRING)
            add(0x5B, ESCAPE, CLEAR, CSI_ENTRY)
            add(r(0x40, 0x7F), CSI_ENTRY, CSI_DISPATCH, GROUND)
            add(r(0x30, 0x3A), CSI_ENTRY, PARAM, CSI_PARAM)
            add(0x3B, CSI_ENTRY, PARAM, CSI_PARAM)
            add(listOf(0x3C, 0x3D, 0x3E, 0x3F), CSI_ENTRY, COLLECT, CSI_PARAM)
            add(r(0x30, 0x3A), CSI_PARAM, PARAM, CSI_PARAM)
            add(0x3B, CSI_PARAM, PARAM, CSI_PARAM)
            add(r(0x40, 0x7F), CSI_PARAM, CSI_DISPATCH, GROUND)
            add(listOf(0x3C, 0x3D, 0x3E, 0x3F), CSI_PARAM, IGNORE, CSI_IGNORE)
            add(0x3A, CSI_PARAM, PARAM, CSI_PARAM)
            add(r(0x20, 0x40), CSI_IGNORE, IGNORE, CSI_IGNORE)
            add(0x7F, CSI_IGNORE, IGNORE, CSI_IGNORE)
            add(r(0x40, 0x7F), CSI_IGNORE, IGNORE, GROUND)
            add(r(0x20, 0x30), CSI_ENTRY, COLLECT, CSI_INTERMEDIATE)
            add(r(0x20, 0x30), CSI_INTERMEDIATE, COLLECT, CSI_INTERMEDIATE)
            add(r(0x30, 0x40), CSI_INTERMEDIATE, IGNORE, CSI_IGNORE)
            add(r(0x40, 0x7F), CSI_INTERMEDIATE, CSI_DISPATCH, GROUND)
            add(r(0x20, 0x30), CSI_PARAM, COLLECT, CSI_INTERMEDIATE)
            add(r(0x20, 0x30), ESCAPE, COLLECT, ESCAPE_INTERMEDIATE)
            add(r(0x20, 0x30), ESCAPE_INTERMEDIATE, COLLECT, ESCAPE_INTERMEDIATE)
            add(r(0x30, 0x7F), ESCAPE_INTERMEDIATE, ESC_DISPATCH, GROUND)
            add(r(0x30, 0x50), ESCAPE, ESC_DISPATCH, GROUND)
            add(r(0x51, 0x58), ESCAPE, ESC_DISPATCH, GROUND)
            add(listOf(0x59, 0x5A, 0x5C), ESCAPE, ESC_DISPATCH, GROUND)
            add(r(0x60, 0x7F), ESCAPE, ESC_DISPATCH, GROUND)
            add(0x50, ESCAPE, CLEAR, DCS_ENTRY)
            add(executables, DCS_ENTRY, IGNORE, DCS_ENTRY)
            add(0x7F, DCS_ENTRY, IGNORE, DCS_ENTRY)
            add(r(0x1C, 0x20), DCS_ENTRY, IGNORE, DCS_ENTRY)
            add(r(0x20, 0x30), DCS_ENTRY, COLLECT, DCS_INTERMEDIATE)
            add(0x3A, DCS_ENTRY, IGNORE, DCS_IGNORE)
            add(r(0x30, 0x3A), DCS_ENTRY, PARAM, DCS_PARAM)
            add(0x3B, DCS_ENTRY, PARAM, DCS_PARAM)
            add(listOf(0x3C, 0x3D, 0x3E, 0x3F), DCS_ENTRY, COLLECT, DCS_PARAM)
            add(executables, DCS_IGNORE, IGNORE, DCS_IGNORE)
            add(r(0x20, 0x80), DCS_IGNORE, IGNORE, DCS_IGNORE)
            add(r(0x1C, 0x20), DCS_IGNORE, IGNORE, DCS_IGNORE)
            add(executables, DCS_PARAM, IGNORE, DCS_PARAM)
            add(0x7F, DCS_PARAM, IGNORE, DCS_PARAM)
            add(r(0x1C, 0x20), DCS_PARAM, IGNORE, DCS_PARAM)
            add(r(0x30, 0x3A), DCS_PARAM, PARAM, DCS_PARAM)
            add(0x3B, DCS_PARAM, PARAM, DCS_PARAM)
            add(listOf(0x3A, 0x3C, 0x3D, 0x3E, 0x3F), DCS_PARAM, IGNORE, DCS_IGNORE)
            add(r(0x20, 0x30), DCS_PARAM, COLLECT, DCS_INTERMEDIATE)
            add(executables, DCS_INTERMEDIATE, IGNORE, DCS_INTERMEDIATE)
            add(0x7F, DCS_INTERMEDIATE, IGNORE, DCS_INTERMEDIATE)
            add(r(0x1C, 0x20), DCS_INTERMEDIATE, IGNORE, DCS_INTERMEDIATE)
            add(r(0x20, 0x30), DCS_INTERMEDIATE, COLLECT, DCS_INTERMEDIATE)
            add(r(0x30, 0x40), DCS_INTERMEDIATE, IGNORE, DCS_IGNORE)
            add(r(0x40, 0x7F), DCS_INTERMEDIATE, DCS_HOOK, DCS_PASSTHROUGH)
            add(r(0x40, 0x7F), DCS_PARAM, DCS_HOOK, DCS_PASSTHROUGH)
            add(r(0x40, 0x7F), DCS_ENTRY, DCS_HOOK, DCS_PASSTHROUGH)
            add(executables, DCS_PASSTHROUGH, DCS_PUT, DCS_PASSTHROUGH)
            add(printables, DCS_PASSTHROUGH, DCS_PUT, DCS_PASSTHROUGH)
            add(0x7F, DCS_PASSTHROUGH, IGNORE, DCS_PASSTHROUGH)
            add(listOf(0x1B, 0x9C), DCS_PASSTHROUGH, DCS_UNHOOK, GROUND)
            add(0xA0, OSC_STRING, OSC_PUT, OSC_STRING)
            add(0xA0, APC_STRING, OSC_PUT, APC_STRING)
        }

        val ASCII = Array(128) { it.toChar().toString() }

        /** UTF-8 sequence length from its first byte: 1 for ASCII, -1 for a byte no sequence starts with. */
        fun expectedSize(byte: Int): Int = when (byte) {
            in 0x00..0x7F -> 1
            in 0xC2..0xDF -> 2
            in 0xE0..0xEF -> 3
            in 0xF0..0xF4 -> 4
            else -> -1
        }

        /** The scalar a whole sequence encodes, or null when it is malformed, overlong or a surrogate. */
        fun decodeUtf8(bytes: ByteArray): Int? {
            val b = IntArray(bytes.size) { bytes[it].toInt() and 0xFF }
            fun cont(i: Int, low: Int = 0x80, high: Int = 0xBF) = b[i] in low..high
            return when (b.size) {
                2 -> if (cont(1)) ((b[0] and 0x1F) shl 6) or (b[1] and 0x3F) else null
                3 -> {
                    val second = when (b[0]) { 0xE0 -> cont(1, 0xA0); 0xED -> cont(1, high = 0x9F); else -> cont(1) }
                    if (second && cont(2)) ((b[0] and 0x0F) shl 12) or ((b[1] and 0x3F) shl 6) or (b[2] and 0x3F) else null
                }
                4 -> {
                    val second = when (b[0]) { 0xF0 -> cont(1, 0x90); 0xF4 -> cont(1, high = 0x8F); else -> cont(1) }
                    if (second && cont(2) && cont(3)) {
                        ((b[0] and 0x07) shl 18) or ((b[1] and 0x3F) shl 12) or ((b[2] and 0x3F) shl 6) or (b[3] and 0x3F)
                    } else null
                }
                else -> null
            }
        }
    }
}
