package com.tddworks.claudebar.datasources.process

/**
 * What a terminal knows about one character: how many columns it takes, and whether it
 * joins the one before it. The rules and tables are SwiftTerm's (1.12), so a screen reads
 * the same as it did; Unicode properties Kotlin common code can't ask for a supplementary
 * code point are approximated by the ranges below.
 */
internal object TerminalGlyphs {
    const val ZERO_WIDTH_JOINER = 0x200D

    /** Columns a code point takes: 0 joins or vanishes, -1 is a control and is never printed. */
    fun columnWidth(code: Int): Int {
        if (code == 0) return 0
        if (code < 0x20) return -1
        if (code < 0x7F) return 1
        if (code < 0xA0) return -1
        when (category(code)) {
            CharCategory.NON_SPACING_MARK, CharCategory.COMBINING_SPACING_MARK, CharCategory.ENCLOSING_MARK -> return 0
            CharCategory.FORMAT -> return if (code == 0x00AD) 1 else 0
            CharCategory.LINE_SEPARATOR, CharCategory.PARAGRAPH_SEPARATOR -> return 0
            CharCategory.MODIFIER_SYMBOL -> {
                if (isEmojiModifier(code)) return 0
                if (code == 0xFF3E || code == 0xFF40 || code == 0xFFE3) return 2
            }
            else -> Unit
        }
        if (code in 0x1160..0x11FF || code in 0xD7B0..0xD7FF) return 0
        if (isRegionalIndicator(code)) return 2
        if (inRanges(code, eastAsianWide)) return 2
        return 1
    }

    fun isRegionalIndicator(code: Int) = code in 0x1F1E6..0x1F1FF
    fun isEmojiModifier(code: Int) = code in 0x1F3FB..0x1F3FF
    fun isVariationSelector(code: Int) =
        code in 0xFE00..0xFE0F || code in 0xE0100..0xE01EF || code in 0x180B..0x180D || code == 0x180F
    fun isEmojiVs16Base(code: Int) = inRanges(code, emojiVs16Base)

    /** A mark that attaches to the character before it, as a combining class other than 0 does. */
    fun isMark(code: Int) = when (category(code)) {
        CharCategory.NON_SPACING_MARK, CharCategory.COMBINING_SPACING_MARK, CharCategory.ENCLOSING_MARK -> true
        else -> false
    }

    /** Whether [text] followed by [code] is still one user-perceived character (UAX #29, the rules a TUI meets). */
    fun joins(text: String, code: Int): Boolean {
        val last = lastCodePoint(text) ?: return false
        if (isControl(last) || isControl(code)) return false
        if (hangulJoins(last, code)) return true
        if (isExtend(code) || code == ZERO_WIDTH_JOINER) return true
        if (last == ZERO_WIDTH_JOINER && isPictographic(code) && codePoints(text).any(::isPictographic)) return true
        if (isRegionalIndicator(last) && isRegionalIndicator(code)) {
            return codePoints(text).count(::isRegionalIndicator) % 2 == 1
        }
        return false
    }

    fun codePoints(text: String): List<Int> {
        val points = ArrayList<Int>(text.length)
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (c.isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) {
                points += 0x10000 + ((c.code - 0xD800) shl 10) + (text[i + 1].code - 0xDC00)
                i += 2
            } else {
                points += c.code
                i += 1
            }
        }
        return points
    }

    fun string(code: Int): String = if (code < 0x10000) code.toChar().toString() else {
        val v = code - 0x10000
        charArrayOf((0xD800 + (v shr 10)).toChar(), (0xDC00 + (v and 0x3FF)).toChar()).concatToString()
    }

    private fun lastCodePoint(text: String): Int? = codePoints(text).lastOrNull()

    private fun isControl(code: Int): Boolean = when {
        code < 0x20 || code in 0x7F..0x9F -> true
        code == ZERO_WIDTH_JOINER || code == 0x200C -> false
        code in 0xE0020..0xE007F -> false
        else -> when (category(code)) {
            CharCategory.FORMAT, CharCategory.LINE_SEPARATOR, CharCategory.PARAGRAPH_SEPARATOR,
            CharCategory.CONTROL, CharCategory.SURROGATE -> true
            else -> false
        }
    }

    private fun isExtend(code: Int) = isMark(code) || isEmojiModifier(code) || isVariationSelector(code) ||
        code == 0x200C || code in 0xE0020..0xE007F || code == 0xFF9E || code == 0xFF9F

    private fun isPictographic(code: Int) = code in 0x1F000..0x1FAFF || code in 0x2600..0x27BF ||
        code in 0x2300..0x23FF || code in 0x2B00..0x2BFF || isEmojiVs16Base(code) && code > 0x7F

    private fun hangulJoins(last: Int, code: Int): Boolean {
        val l = { c: Int -> c in 0x1100..0x115F || c in 0xA960..0xA97C }
        val v = { c: Int -> c in 0x1160..0x11A7 || c in 0xD7B0..0xD7C6 }
        val t = { c: Int -> c in 0x11A8..0x11FF || c in 0xD7CB..0xD7FB }
        val lv = { c: Int -> c in 0xAC00..0xD7A3 && (c - 0xAC00) % 28 == 0 }
        val lvt = { c: Int -> c in 0xAC00..0xD7A3 && (c - 0xAC00) % 28 != 0 }
        return (l(last) && (l(code) || v(code) || lv(code) || lvt(code))) ||
            ((lv(last) || v(last)) && (v(code) || t(code))) ||
            ((lvt(last) || t(last)) && t(code))
    }

    /** A code point's general category; above the BMP only the ranges a terminal meets are known. */
    private fun category(code: Int): CharCategory = when {
        code < 0x10000 -> code.toChar().category
        code in 0xE0100..0xE01EF -> CharCategory.NON_SPACING_MARK
        code == 0xE0001 || code in 0xE0020..0xE007F -> CharCategory.FORMAT
        code in 0x1F3FB..0x1F3FF -> CharCategory.MODIFIER_SYMBOL
        code in 0x1D165..0x1D166 || code in 0x1D16D..0x1D172 -> CharCategory.COMBINING_SPACING_MARK
        code in 0x1D167..0x1D169 || code in 0x1D17B..0x1D182 || code in 0x1D185..0x1D18B ||
            code in 0x1D1AA..0x1D1AD || code in 0x1E8D0..0x1E8D6 || code in 0x1E944..0x1E94A -> CharCategory.NON_SPACING_MARK
        else -> CharCategory.OTHER_SYMBOL
    }

    private fun inRanges(code: Int, ranges: IntArray): Boolean {
        var low = 0
        var high = ranges.size / 2 - 1
        if (code < ranges[0] || code > ranges[ranges.size - 1]) return false
        while (low <= high) {
            val mid = (low + high) / 2
            when {
                code > ranges[mid * 2 + 1] -> low = mid + 1
                code < ranges[mid * 2] -> high = mid - 1
                else -> return true
            }
        }
        return false
    }

    // Generated from SwiftTerm's UnicodeWidthData.swift.
    /** 123 ranges, low and high in turn. */
    private val eastAsianWide = intArrayOf(
        0x1100, 0x115F, 0x231A, 0x231B, 0x2329, 0x232A, 0x23E9, 0x23EC,
        0x23F0, 0x23F0, 0x23F3, 0x23F3, 0x25FD, 0x25FE, 0x2614, 0x2615,
        0x2630, 0x2637, 0x2648, 0x2653, 0x267F, 0x267F, 0x268A, 0x268F,
        0x2693, 0x2693, 0x26A1, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE,
        0x26C4, 0x26C5, 0x26CE, 0x26CE, 0x26D4, 0x26D4, 0x26EA, 0x26EA,
        0x26F2, 0x26F3, 0x26F5, 0x26F5, 0x26FA, 0x26FA, 0x26FD, 0x26FD,
        0x2705, 0x2705, 0x270A, 0x270B, 0x2728, 0x2728, 0x274C, 0x274C,
        0x274E, 0x274E, 0x2753, 0x2755, 0x2757, 0x2757, 0x2795, 0x2797,
        0x27B0, 0x27B0, 0x27BF, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B50,
        0x2B55, 0x2B55, 0x2E80, 0x2E99, 0x2E9B, 0x2EF3, 0x2F00, 0x2FD5,
        0x2FF0, 0x303E, 0x3041, 0x3096, 0x3099, 0x30FF, 0x3105, 0x312F,
        0x3131, 0x318E, 0x3190, 0x31E5, 0x31EF, 0x321E, 0x3220, 0x3247,
        0x3250, 0xA48C, 0xA490, 0xA4C6, 0xA960, 0xA97C, 0xAC00, 0xD7A3,
        0xF900, 0xFAFF, 0xFE10, 0xFE19, 0xFE30, 0xFE52, 0xFE54, 0xFE66,
        0xFE68, 0xFE6B, 0xFF01, 0xFF60, 0xFFE0, 0xFFE6, 0x16FE0, 0x16FE4,
        0x16FF0, 0x16FF6, 0x17000, 0x18CD5, 0x18CFF, 0x18D1E, 0x18D80, 0x18DF2,
        0x1AFF0, 0x1AFF3, 0x1AFF5, 0x1AFFB, 0x1AFFD, 0x1AFFE, 0x1B000, 0x1B122,
        0x1B132, 0x1B132, 0x1B150, 0x1B152, 0x1B155, 0x1B155, 0x1B164, 0x1B167,
        0x1B170, 0x1B2FB, 0x1D300, 0x1D356, 0x1D360, 0x1D376, 0x1F004, 0x1F004,
        0x1F0CF, 0x1F0CF, 0x1F18E, 0x1F18E, 0x1F191, 0x1F19A, 0x1F200, 0x1F202,
        0x1F210, 0x1F23B, 0x1F240, 0x1F248, 0x1F250, 0x1F251, 0x1F260, 0x1F265,
        0x1F300, 0x1F320, 0x1F32D, 0x1F335, 0x1F337, 0x1F37C, 0x1F37E, 0x1F393,
        0x1F3A0, 0x1F3CA, 0x1F3CF, 0x1F3D3, 0x1F3E0, 0x1F3F0, 0x1F3F4, 0x1F3F4,
        0x1F3F8, 0x1F43E, 0x1F440, 0x1F440, 0x1F442, 0x1F4FC, 0x1F4FF, 0x1F53D,
        0x1F54B, 0x1F54E, 0x1F550, 0x1F567, 0x1F57A, 0x1F57A, 0x1F595, 0x1F596,
        0x1F5A4, 0x1F5A4, 0x1F5FB, 0x1F64F, 0x1F680, 0x1F6C5, 0x1F6CC, 0x1F6CC,
        0x1F6D0, 0x1F6D2, 0x1F6D5, 0x1F6D8, 0x1F6DC, 0x1F6DF, 0x1F6EB, 0x1F6EC,
        0x1F6F4, 0x1F6FC, 0x1F7E0, 0x1F7EB, 0x1F7F0, 0x1F7F0, 0x1F90C, 0x1F93A,
        0x1F93C, 0x1F945, 0x1F947, 0x1F9FF, 0x1FA70, 0x1FA7C, 0x1FA80, 0x1FA8A,
        0x1FA8E, 0x1FAC6, 0x1FAC8, 0x1FAC8, 0x1FACD, 0x1FADC, 0x1FADF, 0x1FAEA,
        0x1FAEF, 0x1FAF8, 0x20000, 0x2FFFD, 0x30000, 0x3FFFD,
    )

    /** 183 ranges, low and high in turn. */
    private val emojiVs16Base = intArrayOf(
        0x0023, 0x0023, 0x002A, 0x002A, 0x0030, 0x0039, 0x00A9, 0x00A9,
        0x00AE, 0x00AE, 0x203C, 0x203C, 0x2049, 0x2049, 0x2122, 0x2122,
        0x2139, 0x2139, 0x2194, 0x2199, 0x21A9, 0x21AA, 0x231A, 0x231B,
        0x2328, 0x2328, 0x23CF, 0x23CF, 0x23E9, 0x23F3, 0x23F8, 0x23FA,
        0x24C2, 0x24C2, 0x25AA, 0x25AB, 0x25B6, 0x25B6, 0x25C0, 0x25C0,
        0x25FB, 0x25FE, 0x2600, 0x2604, 0x260E, 0x260E, 0x2611, 0x2611,
        0x2614, 0x2615, 0x2618, 0x2618, 0x261D, 0x261D, 0x2620, 0x2620,
        0x2622, 0x2623, 0x2626, 0x2626, 0x262A, 0x262A, 0x262E, 0x262F,
        0x2638, 0x263A, 0x2640, 0x2640, 0x2642, 0x2642, 0x2648, 0x2653,
        0x265F, 0x2660, 0x2663, 0x2663, 0x2665, 0x2666, 0x2668, 0x2668,
        0x267B, 0x267B, 0x267E, 0x267F, 0x2692, 0x2697, 0x2699, 0x2699,
        0x269B, 0x269C, 0x26A0, 0x26A1, 0x26A7, 0x26A7, 0x26AA, 0x26AB,
        0x26B0, 0x26B1, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26C8, 0x26C8,
        0x26CE, 0x26CF, 0x26D1, 0x26D1, 0x26D3, 0x26D4, 0x26E9, 0x26EA,
        0x26F0, 0x26F5, 0x26F7, 0x26FA, 0x26FD, 0x26FD, 0x2702, 0x2702,
        0x2705, 0x2705, 0x2708, 0x270D, 0x270F, 0x270F, 0x2712, 0x2712,
        0x2714, 0x2714, 0x2716, 0x2716, 0x271D, 0x271D, 0x2721, 0x2721,
        0x2728, 0x2728, 0x2733, 0x2734, 0x2744, 0x2744, 0x2747, 0x2747,
        0x274C, 0x274C, 0x274E, 0x274E, 0x2753, 0x2755, 0x2757, 0x2757,
        0x2763, 0x2764, 0x2795, 0x2797, 0x27A1, 0x27A1, 0x27B0, 0x27B0,
        0x27BF, 0x27BF, 0x2934, 0x2935, 0x2B05, 0x2B07, 0x2B1B, 0x2B1C,
        0x2B50, 0x2B50, 0x2B55, 0x2B55, 0x3030, 0x3030, 0x303D, 0x303D,
        0x3297, 0x3297, 0x3299, 0x3299, 0x1F004, 0x1F004, 0x1F170, 0x1F171,
        0x1F17E, 0x1F17F, 0x1F202, 0x1F202, 0x1F21A, 0x1F21A, 0x1F22F, 0x1F22F,
        0x1F237, 0x1F237, 0x1F30D, 0x1F30F, 0x1F315, 0x1F315, 0x1F31C, 0x1F31C,
        0x1F321, 0x1F321, 0x1F324, 0x1F32C, 0x1F336, 0x1F336, 0x1F378, 0x1F378,
        0x1F37D, 0x1F37D, 0x1F393, 0x1F393, 0x1F396, 0x1F397, 0x1F399, 0x1F39B,
        0x1F39E, 0x1F39F, 0x1F3A7, 0x1F3A7, 0x1F3AC, 0x1F3AE, 0x1F3C2, 0x1F3C2,
        0x1F3C4, 0x1F3C4, 0x1F3C6, 0x1F3C6, 0x1F3CA, 0x1F3CE, 0x1F3D4, 0x1F3E0,
        0x1F3ED, 0x1F3ED, 0x1F3F3, 0x1F3F3, 0x1F3F5, 0x1F3F5, 0x1F3F7, 0x1F3F7,
        0x1F408, 0x1F408, 0x1F415, 0x1F415, 0x1F41F, 0x1F41F, 0x1F426, 0x1F426,
        0x1F43F, 0x1F43F, 0x1F441, 0x1F442, 0x1F446, 0x1F449, 0x1F44D, 0x1F44E,
        0x1F453, 0x1F453, 0x1F46A, 0x1F46A, 0x1F47D, 0x1F47D, 0x1F4A3, 0x1F4A3,
        0x1F4B0, 0x1F4B0, 0x1F4B3, 0x1F4B3, 0x1F4BB, 0x1F4BB, 0x1F4BF, 0x1F4BF,
        0x1F4CB, 0x1F4CB, 0x1F4DA, 0x1F4DA, 0x1F4DF, 0x1F4DF, 0x1F4E4, 0x1F4E6,
        0x1F4EA, 0x1F4ED, 0x1F4F7, 0x1F4F7, 0x1F4F9, 0x1F4FB, 0x1F4FD, 0x1F4FD,
        0x1F508, 0x1F508, 0x1F50D, 0x1F50D, 0x1F512, 0x1F513, 0x1F549, 0x1F54A,
        0x1F550, 0x1F567, 0x1F56F, 0x1F570, 0x1F573, 0x1F579, 0x1F587, 0x1F587,
        0x1F58A, 0x1F58D, 0x1F590, 0x1F590, 0x1F5A5, 0x1F5A5, 0x1F5A8, 0x1F5A8,
        0x1F5B1, 0x1F5B2, 0x1F5BC, 0x1F5BC, 0x1F5C2, 0x1F5C4, 0x1F5D1, 0x1F5D3,
        0x1F5DC, 0x1F5DE, 0x1F5E1, 0x1F5E1, 0x1F5E3, 0x1F5E3, 0x1F5E8, 0x1F5E8,
        0x1F5EF, 0x1F5EF, 0x1F5F3, 0x1F5F3, 0x1F5FA, 0x1F5FA, 0x1F610, 0x1F610,
        0x1F687, 0x1F687, 0x1F68D, 0x1F68D, 0x1F691, 0x1F691, 0x1F694, 0x1F694,
        0x1F698, 0x1F698, 0x1F6AD, 0x1F6AD, 0x1F6B2, 0x1F6B2, 0x1F6B9, 0x1F6BA,
        0x1F6BC, 0x1F6BC, 0x1F6CB, 0x1F6CB, 0x1F6CD, 0x1F6CF, 0x1F6E0, 0x1F6E5,
        0x1F6E9, 0x1F6E9, 0x1F6F0, 0x1F6F0, 0x1F6F3, 0x1F6F3,
    )
}

/** The national and DEC graphics sets `ESC ( x` designates; `B` is US ASCII, an empty map. */
internal object TerminalCharsets {
    private val decGraphics = mapOf(
        '`' to "◆", 'a' to "▒", 'b' to "␉", 'c' to "␌", 'd' to "␍", 'e' to "␊",
        'f' to "°", 'g' to "±", 'h' to "␤", 'i' to "␋", 'j' to "┘", 'k' to "┐",
        'l' to "┌", 'm' to "└", 'n' to "┼", 'o' to "⎺", 'p' to "⎻", 'q' to "─",
        'r' to "⎼", 's' to "⎽", 't' to "├", 'u' to "┤", 'v' to "┴", 'w' to "┬",
        'x' to "│", 'y' to "≤", 'z' to "≥", '{' to "π", '|' to "≠", '}' to "£",
        '~' to "·",
    )
    private val finnish = mapOf('[' to "Ä", '\\' to "Ö", ']' to "Å", '^' to "Ü", '`' to "é", '{' to "ä", '|' to "ö", '}' to "å", '~' to "ü")
    private val norwegian = mapOf('@' to "Ä", '[' to "Æ", '\\' to "Ø", ']' to "Å", '^' to "Ü", '`' to "ä", '{' to "æ", '|' to "ø", '}' to "å", '~' to "ü")
    private val swedish = mapOf('@' to "É", '[' to "Ä", '\\' to "Ö", ']' to "Å", '^' to "Ü", '`' to "é", '{' to "ä", '|' to "ö", '}' to "å", '~' to "ü")

    /** By designator, each mapping a 7-bit code to what it draws. */
    val all: Map<Char, Map<Int, String>> = mapOf(
        '0' to decGraphics,
        '2' to decGraphics,
        'A' to mapOf('#' to "£"),
        'B' to emptyMap(),
        '4' to mapOf('#' to "£", '@' to "¾", '[' to "ĳ", '\\' to "½", ']' to "|", '{' to "¨", '|' to "f", '}' to "¼", '~' to "´"),
        '5' to finnish,
        'C' to finnish,
        'R' to mapOf('#' to "£", '@' to "à", '[' to "°", '\\' to "ç", ']' to "§", '{' to "é", '|' to "ù", '}' to "è", '~' to "¨"),
        'Q' to mapOf('@' to "à", '[' to "â", '\\' to "ç", ']' to "ê", '^' to "î", '`' to "ô", '{' to "é", '|' to "ù", '}' to "è", '~' to "û"),
        'K' to mapOf('@' to "§", '[' to "Ä", '\\' to "Ö", ']' to "Ü", '{' to "ä", '|' to "ö", '}' to "ü", '~' to "ß"),
        'Y' to mapOf('#' to "£", '@' to "§", '[' to "°", '\\' to "ç", ']' to "é", '`' to "ù", '{' to "à", '|' to "ò", '}' to "è", '~' to "ì"),
        '6' to norwegian,
        'E' to norwegian,
        'Z' to mapOf('#' to "£", '@' to "§", '[' to "¡", '\\' to "Ñ", ']' to "¿", '{' to "°", '|' to "ñ", '}' to "ç"),
        '7' to swedish,
        'H' to swedish,
        '=' to mapOf('#' to "ù", '@' to "à", '[' to "é", '\\' to "ç", ']' to "ê", '^' to "î", '_' to "è", '`' to "ô", '{' to "ä", '|' to "ö", '}' to "ü", '~' to "û"),
    ).mapValues { (_, set) -> set.mapKeys { it.key.code } }
}
