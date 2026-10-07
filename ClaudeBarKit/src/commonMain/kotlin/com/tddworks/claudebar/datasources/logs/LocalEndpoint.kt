package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.JsonPath
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readByteArray
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `freeWhen.localEndpoint` — whether a tool is routed at a server on this Mac (ollama, LM
 * Studio, llama.cpp), where nobody bills per token.
 *
 * Reads [file] on every call, so a route switched to a local server counts from the next read
 * without a restart. The first [url] entry that answers decides — a tool's own route outranks
 * a menu of routes it may switch to — and a missing, unreadable or remote URL means "not local".
 */
internal class LocalEndpoint(val file: String, val url: List<List<String>>) {
    fun isLocal(): Boolean {
        val bytes = runCatching { SystemFileSystem.source(Path(file)).buffered().use { it.readByteArray() } }.getOrNull()
            ?: return false
        val root = jsonDocument(bytes) ?: return false
        for (entry in url) {
            val urls = entry.flatMap { strings(it, root) }
            if (urls.isNotEmpty()) return urls.any(::isLoopback)
        }
        return false
    }

    companion object {
        private val loopbackHosts = setOf("localhost", "127.0.0.1", "::1", "0.0.0.0")

        /**
         * Whether a base URL points at this machine. A host that can't be parsed is remote:
         * charging nothing because a URL failed to parse would silently under-report real spend.
         */
        fun isLoopback(baseUrl: String): Boolean {
            val bare = host(baseUrl)?.lowercase()?.trim('[', ']') ?: return false
            return bare in loopbackHosts || bare.endsWith(".localhost")
        }

        /** The texts at a path, where `name[*]` walks every element of a list. */
        fun strings(path: String, root: JsonElement): List<String> {
            val components = path.removePrefix("$.").split('.').filter { it.isNotEmpty() }
            return values(components, root).mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
        }

        private fun values(components: List<String>, value: JsonElement): List<JsonElement> {
            val first = components.firstOrNull() ?: return listOf(value)
            val rest = components.drop(1)
            if (first.endsWith("[*]")) {
                val list = (value as? JsonObject)?.get(first.removeSuffix("[*]")) as? JsonArray ?: return emptyList()
                return list.flatMap { values(rest, it) }
            }
            val next = JsonPath.walk(value, listOf(first)) ?: return emptyList()
            return values(rest, next)
        }

        private val scheme = Regex("^[A-Za-z][A-Za-z0-9+.-]*:")
        private const val URL_CHARACTERS = "-._~:/?#[]@!$&'()*+,;=%"

        /** The host of a URL as URLComponents reads it — brackets kept on an IPv6 literal — or null when it has none or isn't a URL. */
        private fun host(text: String): String? {
            if (text.any { !(it.isLetterOrDigit() && it.code < 128) && it !in URL_CHARACTERS }) return null
            val rest = scheme.find(text)?.let { text.substring(it.range.last + 1) } ?: text
            if (!rest.startsWith("//")) return null
            val authority = rest.substring(2).takeWhile { it !in "/?#" }
            val hostAndPort = authority.substringAfterLast('@')
            return if (hostAndPort.startsWith("[")) {
                hostAndPort.substringBefore(']', missingDelimiterValue = "").takeIf { it.isNotEmpty() }?.plus("]")
            } else {
                hostAndPort.substringBefore(':')
            }
        }
    }
}
