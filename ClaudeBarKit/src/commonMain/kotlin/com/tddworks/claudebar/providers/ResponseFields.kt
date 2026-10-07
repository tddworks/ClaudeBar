package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.Response
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * *Map fields*: what came back, as values to click — every number, string and flag in a JSON
 * response with the path that reaches it (`$.data.limit`), so a person maps *Used · Remaining ·
 * Limit · Resets* by pointing.
 */
public class ResponseFields private constructor(private val fields: List<Field>) {
    /** Every value, sorted by path. */
    val all: List<Field> get() = fields

    val isEmpty: Boolean get() = fields.isEmpty()

    data class Field(val path: String, val value: String, val isNumber: Boolean)

    override fun equals(other: Any?) = other is ResponseFields && other.fields == fields
    override fun hashCode() = fields.hashCode()
    override fun toString() = fields.toString()

    companion object {
        /** Enough to map a response, not to drown in one. */
        private const val LIMIT = 500

        /** No values — before anything came back. */
        val empty: ResponseFields = ResponseFields(emptyList())

        /** The response's values, sorted by path; empty when it isn't JSON. */
        fun of(response: Response): ResponseFields = invoke(response)

        /** The response's values, sorted by path; empty when it isn't JSON. */
        operator fun invoke(response: Response): ResponseFields {
            val document = runCatching { Json.parseToJsonElement(response.text) }.getOrNull() ?: return ResponseFields(emptyList())
            val found = mutableListOf<Field>()
            walk(document, "$", found)
            return ResponseFields(found.sortedBy { it.path })
        }

        /** A text response's non-empty lines — what a CLI printed. */
        fun lines(response: Response): List<String> =
            response.text.split(newlines).map { it.trim() }.filter { it.isNotEmpty() }

        private val newlines = Regex("[\\n\\u000B\\u000C\\r\\u0085\\u2028\\u2029]")

        private fun walk(value: JsonElement, path: String, fields: MutableList<Field>) {
            if (fields.size >= LIMIT) return
            when (value) {
                is JsonObject -> value.keys.sorted().forEach { walk(value.getValue(it), "$path.$it", fields) }
                is JsonArray -> value.forEachIndexed { index, element -> walk(element, "$path.$index", fields) }
                JsonNull -> Unit
                is JsonPrimitive -> fields += when {
                    value.isString -> Field(path, value.content, isNumber = false)
                    value.booleanOrNull != null -> Field(path, value.content, isNumber = false)
                    else -> Field(path, numberText(value.content), isNumber = true)
                }
            }
        }
    }
}

/** A JSON number as `NSNumber.stringValue` writes it: a whole number without its `.0`. */
internal fun numberText(text: String): String {
    text.toLongOrNull()?.let { return it.toString() }
    val value = text.toDoubleOrNull() ?: return text
    return if (value == kotlin.math.floor(value) && kotlin.math.abs(value) < 1e15) value.toLong().toString() else value.toString()
}
