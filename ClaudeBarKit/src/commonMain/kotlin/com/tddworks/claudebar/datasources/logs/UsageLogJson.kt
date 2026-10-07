package com.tddworks.claudebar.datasources.logs

import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.DefinitionJson
import com.tddworks.claudebar.datasources.decoding
import com.tddworks.claudebar.datasources.requireString
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

/**
 * A record's fields sit inline or in `shapes`, never both; in a list every shape has a
 * `where`, so none silently takes another's lines. One shape is written inline, exactly as
 * before `shapes` existed, so its fingerprint — and the days kept under it — stay put.
 */
internal object RecordsSerializer : KSerializer<UsageLog.Records> {
    private val inline = listOf("where", "at", "id", "model", "tokens", "cost")

    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): UsageLog.Records {
        val json = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject
            ?: throw DefinitionError("records is an object")
        val files = json.requireString("files", "records")
        val format = json["format"]?.let { decoding("records.format") { DefinitionJson.decodeFromJsonElement<UsageLog.Format>(it) } }
            ?: UsageLog.Format.JSON_LINES
        val listed = json["shapes"]
            ?: return UsageLog.Records(files, format, listOf(decoding("records") { DefinitionJson.decodeFromJsonElement<UsageLog.Shape>(json) }))
        inline.firstOrNull { it in json }?.let {
            throw DefinitionError("records.$it: a log gives its record's fields inline or in `shapes`, never both")
        }
        val shapes = decoding("records.shapes") { DefinitionJson.decodeFromJsonElement<List<UsageLog.Shape>>(listed) }
        if (shapes.isEmpty() || shapes.any { it.condition == null }) {
            throw DefinitionError("records.shapes lists at least one shape, and every shape has a `where`")
        }
        return UsageLog.Records(files, format, shapes)
    }

    override fun serialize(encoder: Encoder, value: UsageLog.Records) {
        val fields = mutableMapOf<String, JsonElement>(
            "files" to JsonPrimitive(value.files),
            "format" to DefinitionJson.encodeToJsonElement(value.format),
        )
        if (value.shapes.size == 1) {
            fields += DefinitionJson.encodeToJsonElement(value.shapes[0]) as JsonObject
        } else {
            fields["shapes"] = DefinitionJson.encodeToJsonElement(value.shapes)
        }
        (encoder as JsonEncoder).encodeJsonElement(JsonObject(fields))
    }
}

/** `"$.at"` is a field; `{field, format}` a written-out date; `{fromPath, format}` a time in the file's path. */
internal object AtSerializer : KSerializer<UsageLog.At> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): UsageLog.At = when (val json = (decoder as JsonDecoder).decodeJsonElement()) {
        is JsonPrimitive if json.isString -> UsageLog.At.Field(json.content)
        is JsonObject if json["field"] is JsonPrimitive && json["format"] is JsonPrimitive ->
            decoding("at") { DefinitionJson.decodeFromJsonElement<UsageLog.At.Formatted>(json) }
        is JsonObject -> decoding("at") { DefinitionJson.decodeFromJsonElement<UsageLog.At.FromPath>(json) }
        else -> throw DefinitionError("at is a path, {field, format} or {fromPath, format}")
    }

    override fun serialize(encoder: Encoder, value: UsageLog.At) = (encoder as JsonEncoder).encodeJsonElement(
        when (value) {
            is UsageLog.At.Field -> JsonPrimitive(value.path)
            is UsageLog.At.FromPath -> DefinitionJson.encodeToJsonElement(value)
            is UsageLog.At.Formatted -> DefinitionJson.encodeToJsonElement(value)
        },
    )
}

/** `["$.a", ["$.b", "$.c"]]`: each entry one path or a list of them, written back the same way. */
internal object UrlEntriesSerializer : KSerializer<List<List<String>>> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): List<List<String>> {
        val json = (decoder as JsonDecoder).decodeJsonElement() as? JsonArray ?: throw DefinitionError("url is a list")
        return json.map { entry ->
            when (entry) {
                is JsonPrimitive if entry.isString -> listOf(entry.content)
                is JsonArray -> entry.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: throw DefinitionError("url holds paths") }
                else -> throw DefinitionError("url holds paths, or lists of them")
            }
        }
    }

    override fun serialize(encoder: Encoder, value: List<List<String>>) = (encoder as JsonEncoder).encodeJsonElement(
        JsonArray(value.map { if (it.size == 1) JsonPrimitive(it[0]) else JsonArray(it.map(::JsonPrimitive)) }),
    )
}

/**
 * JSON written byte for byte as Swift's `JSONEncoder` with `.sortedKeys` writes it — keys
 * sorted, `/` escaped, a whole number without `.0` — so a fingerprint taken here equals the
 * one the Swift app kept, and switching over doesn't sum every kept day again.
 */
internal object SwiftJson {
    fun encode(json: JsonElement): String = StringBuilder().also { write(json, it) }.toString()

    private fun write(json: JsonElement, out: StringBuilder) {
        when (json) {
            is JsonNull -> out.append("null")
            is JsonObject -> {
                out.append('{')
                json.keys.sorted().forEachIndexed { index, key ->
                    if (index > 0) out.append(',')
                    string(key, out)
                    out.append(':')
                    write(json.getValue(key), out)
                }
                out.append('}')
            }
            is JsonArray -> {
                out.append('[')
                json.forEachIndexed { index, item ->
                    if (index > 0) out.append(',')
                    write(item, out)
                }
                out.append(']')
            }
            is JsonPrimitive -> when {
                json.isString -> string(json.content, out)
                json.booleanOrNull != null -> out.append(json.content)
                else -> out.append(number(json.content))
            }
        }
    }

    private fun number(text: String): String {
        val value = text.toDoubleOrNull() ?: return text
        return if (value == kotlin.math.floor(value) && kotlin.math.abs(value) < 1e15) value.toLong().toString() else value.toString()
    }

    private fun string(text: String, out: StringBuilder) {
        out.append('"')
        for (char in text) {
            when (char) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '/' -> out.append("\\/")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (char < ' ') out.append("\\u").append(char.code.toString(16).padStart(4, '0')) else out.append(char)
            }
        }
        out.append('"')
    }
}
