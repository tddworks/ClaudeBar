package com.tddworks.claudebar.storage

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString
import kotlinx.io.writeString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `~/.claudebar/settings.json` — one file every context's settings live in, read and written
 * by dotted name (`app.themeMode`). A write keeps every setting it doesn't touch, including
 * ones this version doesn't know; writing null forgets a setting. A missing or broken file
 * reads as no settings, and the next write replaces it with a readable one.
 */
class SettingsFile(val path: String) {
    private val file = Path(path)
    private val lock = SynchronizedObject()

    /** The setting under a dotted name, or null. */
    fun read(key: String): JsonElement? = synchronized(lock) { find(readFile(), key.split('.')) }

    /** Saves a setting under a dotted name, creating the sections it needs; null forgets it. */
    fun write(key: String, value: JsonElement?) = synchronized(lock) {
        writeFile(put(readFile(), key.split('.'), value))
    }

    /** Every setting in the file. */
    fun readAll(): JsonObject = synchronized(lock) { readFile() }

    fun string(key: String): String? = (read(key) as? JsonPrimitive)?.takeIf { it.isString }?.content

    // JSON text in and out, for Swift, which keeps reading settings as Foundation values.
    fun readJson(key: String): String? = read(key)?.toString()

    fun writeJson(key: String, json: String?) = write(key, json?.let { Json.parseToJsonElement(it) })

    fun readAllJson(): String = readAll().toString()

    private fun readFile(): JsonObject = runCatching {
        SystemFileSystem.source(file).buffered().use { Json.parseToJsonElement(it.readString()) } as? JsonObject
    }.getOrNull() ?: JsonObject(emptyMap())

    private fun writeFile(settings: JsonObject) {
        runCatching {
            file.parent?.let { SystemFileSystem.createDirectories(it) }
            val temporary = Path("$path.writing")
            SystemFileSystem.sink(temporary).buffered().use { it.writeString(pretty(settings, "") + "\n") }
            SystemFileSystem.atomicMove(temporary, file)
        }
    }

    private fun find(settings: JsonObject, parts: List<String>): JsonElement? {
        val value = settings[parts.first()] ?: return null
        if (parts.size == 1) return value.takeUnless { it is JsonNull }
        return (value as? JsonObject)?.let { find(it, parts.drop(1)) }
    }

    private fun put(settings: JsonObject, parts: List<String>, value: JsonElement?): JsonObject {
        val updated = settings.toMutableMap()
        val name = parts.first()
        if (parts.size == 1) {
            if (value == null) updated.remove(name) else updated[name] = value
        } else {
            val section = settings[name] as? JsonObject ?: JsonObject(emptyMap())
            updated[name] = put(section, parts.drop(1), value)
        }
        return JsonObject(updated)
    }

    /** Two-space indents and sorted names, so the file reads and diffs the way it always has. */
    private fun pretty(element: JsonElement, indent: String): String {
        val inner = "$indent  "
        return when (element) {
            is JsonObject -> if (element.isEmpty()) "{}" else element.entries.sortedBy { it.key }
                .joinToString(",\n", "{\n", "\n$indent}") { (name, value) ->
                    "$inner${JsonPrimitive(name)} : ${pretty(value, inner)}"
                }
            is JsonArray -> if (element.isEmpty()) "[]" else element
                .joinToString(",\n", "[\n", "\n$indent]") { "$inner${pretty(it, inner)}" }
            else -> element.toString()
        }
    }
}
