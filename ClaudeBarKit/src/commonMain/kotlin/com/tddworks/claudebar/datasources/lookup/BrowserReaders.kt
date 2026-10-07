package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.BrowserStorageReading
import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.CredentialFinding
import com.tddworks.claudebar.datasources.FoundCredential
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** `browserCookies` — the first store holding a named, non-empty cookie answers. */
internal class BrowserCookieReader(val query: BrowserCookieCredential, private val cookies: BrowserCookieReading) : CredentialFinding {
    override fun find(): FoundCredential? {
        for (store in cookies.stores(query.domains, query.names)) {
            val present = store.filter { it.name in query.names && it.value.isNotEmpty() }
            val first = present.firstOrNull() ?: continue
            val token = when (query.format) {
                BrowserCookieCredential.Format.VALUE -> first.value
                BrowserCookieCredential.Format.HEADER -> present.joinToString("; ") { "${it.name}=${it.value}" }
            }
            return FoundCredential(Credential(mapOf("token" to token)))
        }
        return null
    }
}

/**
 * `browserStorage` — every value from the first browser profile that keeps a token for the site;
 * never one profile's token with another's values.
 */
internal class BrowserStorageReader(val query: BrowserStorageCredential, private val storage: BrowserStorageReading) : CredentialFinding {
    override fun find(): FoundCredential? {
        for (store in storage.stores(query.origin)) {
            val values = query.values.mapNotNull { (name, rule) -> value(rule, store)?.let { name to it } }.toMap()
            if (values["token"].isNullOrEmpty()) continue
            return FoundCredential(Credential(values))
        }
        return null
    }

    /** The first key, in name order, the rule's pattern matches, read at its path when it has one; a JSON string is unquoted. */
    private fun value(rule: BrowserStorageCredential.Value, store: Map<String, String>): String? {
        for (key in store.keys.filter { Fnmatch.matches(rule.key, it) }.sorted()) {
            val raw = store[key] ?: continue
            val json = runCatching { Json.parseToJsonElement(raw) }.getOrNull()
            val value = if (rule.path != null) {
                (json as? JsonObject)?.let { CredentialDocument.values(mapOf("value" to rule.path), it)["value"] }
            } else {
                (json as? JsonPrimitive)?.takeIf { it.isString }?.content ?: raw
            }
            value?.let(::trimmed)?.takeIf { it.isNotEmpty() }?.let { return it }
        }
        return null
    }
}

/** POSIX `fnmatch` with no flags: `*`, `?`, `[set]` (`!` negates, `a-z` ranges) and `\` escapes; `/` is not special. */
internal object Fnmatch {
    fun matches(pattern: String, text: String): Boolean = match(pattern, 0, text, 0)

    private fun match(pattern: String, p: Int, text: String, t: Int): Boolean {
        if (p == pattern.length) return t == text.length
        return when (pattern[p]) {
            '*' -> (t..text.length).any { match(pattern, p + 1, text, it) }
            '?' -> t < text.length && match(pattern, p + 1, text, t + 1)
            '[' -> {
                val set = bracket(pattern, p) ?: return literal(pattern, p, '[', text, t)
                t < text.length && set.first(text[t]) && match(pattern, set.second, text, t + 1)
            }
            '\\' -> if (p + 1 < pattern.length) literal(pattern, p + 1, pattern[p + 1], text, t) else literal(pattern, p, '\\', text, t)
            else -> literal(pattern, p, pattern[p], text, t)
        }
    }

    private fun literal(pattern: String, p: Int, char: Char, text: String, t: Int) =
        t < text.length && text[t] == char && match(pattern, p + 1, text, t + 1)

    /** The set's test and the index after its `]`, or null when the bracket never closes. */
    private fun bracket(pattern: String, start: Int): Pair<(Char) -> Boolean, Int>? {
        var index = start + 1
        val negated = index < pattern.length && (pattern[index] == '!' || pattern[index] == '^')
        if (negated) index++
        val ranges = mutableListOf<CharRange>()
        var first = true
        while (index < pattern.length && (first || pattern[index] != ']')) {
            first = false
            val low = pattern[index]
            if (index + 2 < pattern.length && pattern[index + 1] == '-' && pattern[index + 2] != ']') {
                ranges += low..pattern[index + 2]
                index += 3
            } else {
                ranges += low..low
                index++
            }
        }
        if (index >= pattern.length) return null
        return Pair({ char: Char -> ranges.any { char in it } != negated }, index + 1)
    }
}
