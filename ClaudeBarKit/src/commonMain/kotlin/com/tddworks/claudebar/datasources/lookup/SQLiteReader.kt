package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.CredentialFinding
import com.tddworks.claudebar.datasources.FoundCredential
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.Paths
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SQLiteCall
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** One column of a row as SQLite holds it: TEXT, INTEGER and REAL as SQLite prints them, a BLOB as its bytes. */
internal sealed class StoredValue {
    data class Text(val text: String) : StoredValue()

    class Bytes(val bytes: ByteArray) : StoredValue() {
        override fun equals(other: Any?) = other is Bytes && other.bytes.contentEquals(bytes)
        override fun hashCode() = bytes.contentHashCode()
    }
}

/**
 * Another app's SQLite database, opened read-only — the port the `sqlite` lookup, the `sqlite`
 * fetch and the browsers' cookie stores read through. A statement that would change the database
 * is refused before it runs (`UsageError.ExecutionFailed`); NULL columns are left out.
 */
internal interface SQLiteReading {
    /** At most [limit] rows of [query] against the database at [path]; [name] is how a failure calls it. */
    fun rows(path: String, query: String, name: String, limit: Int = ReadOnlyQuery.ROW_LIMIT): List<Map<String, StoredValue>>
}

/**
 * A query against another app's own database, read and never written — shared by the `sqlite` key
 * lookup and the `sqlite` fetch (ENGINE_DESIGN §2.9). Each column comes back as text: TEXT as it
 * is, a BLOB as the UTF-8 or UTF-16LE text an app stored in it.
 */
internal object ReadOnlyQuery {
    /** At most this many rows and bytes per value, so an unexpected table can't flood a mapping. */
    const val ROW_LIMIT = 1_000
    const val VALUE_LIMIT = 1_048_576

    fun rows(database: SQLiteReading, path: String, query: String, name: String): List<Map<String, String>> =
        database.rows(path, query, name).map { row ->
            row.mapNotNull { (column, value) ->
                when (value) {
                    is StoredValue.Text -> value.text.takeIf { it.encodeToByteArray().size <= VALUE_LIMIT }
                    is StoredValue.Bytes -> value.bytes.takeIf { it.size <= VALUE_LIMIT }?.let(StoredText::decode)
                }?.let { column to it }
            }.toMap()
        }
}

/** The text an app stored as bytes. */
internal object StoredText {
    /** UTF-8, or UTF-16LE when every other byte of it is a zero, as plain text in UTF-16 is. */
    fun decode(bytes: ByteArray): String {
        val looksUTF16 = bytes.size >= 2 && bytes.size % 2 == 0 && (1 until bytes.size step 2).any { bytes[it] == 0.toByte() }
        if (looksUTF16) utf16LittleEndian(bytes)?.let { return it }
        return bytes.decodeToString()
    }

    /** null when the bytes aren't whole UTF-16LE code units with paired surrogates. */
    fun utf16LittleEndian(bytes: ByteArray): String? {
        if (bytes.size % 2 != 0) return null
        val chars = CharArray(bytes.size / 2) {
            ((bytes[it * 2].toInt() and 0xFF) or ((bytes[it * 2 + 1].toInt() and 0xFF) shl 8)).toChar()
        }
        var index = 0
        while (index < chars.size) {
            val char = chars[index]
            if (char.isHighSurrogate()) {
                if (index + 1 >= chars.size || !chars[index + 1].isLowSurrogate()) return null
                index += 2
            } else if (char.isLowSurrogate()) {
                return null
            } else {
                index++
            }
        }
        return chars.concatToString()
    }

    /** UTF-8, or null when the bytes aren't valid UTF-8. */
    fun utf8(bytes: ByteArray): String? = runCatching { bytes.decodeToString(throwOnInvalidSequence = true) }.getOrNull()

    /** ISO 8859-1: every byte is the character of its value. */
    fun latin1(bytes: ByteArray): String = CharArray(bytes.size) { (bytes[it].toInt() and 0xFF).toChar() }.concatToString()
}

/**
 * `sqlite` — the first row of a read-only query against another app's own database, through
 * [ReadOnlyQuery], so ClaudeBar never writes, creates or copies it.
 */
internal class SQLiteReader(
    val file: SQLiteCredential,
    private val database: SQLiteReading,
    private val home: String,
    private val environment: (String) -> String?,
) : CredentialFinding {
    override fun find(): FoundCredential? {
        val path = Paths.resolve(file.path, home, environment)
        if (!SystemFileSystem.exists(Path(path))) return null
        val row = ReadOnlyQuery.rows(database, path, file.query, file.path.toString()).firstOrNull() ?: return null
        val values = CredentialDocument.values(file.fields, JsonObject(row.mapValues { JsonPrimitive(it.value) }))
        if (values["token"] == null) return null
        return FoundCredential(Credential(values))
    }
}

/**
 * `sqlite` as a fetch — the rows of a read-only query against an app's own database are the
 * answer, `[{column: text}]`. Ready while the database is there.
 */
internal class SQLiteFetcher(
    val call: SQLiteCall,
    private val database: SQLiteReading,
    private val home: String,
    private val environment: (String) -> String?,
) : Fetching {
    private val path: String get() = Paths.resolve(call.path, home, environment)

    override fun isReady(): Boolean = SystemFileSystem.exists(Path(path))

    override suspend fun fetch(credential: Credential?): Response = withContext(Dispatchers.IO) {
        val path = path
        if (!SystemFileSystem.exists(Path(path))) throw UsageError.ExecutionFailed("No database at ${call.path}")
        val rows = ReadOnlyQuery.rows(database, path, call.query, call.path.toString())
        val json = JsonArray(rows.map { row -> JsonObject(row.entries.sortedBy { it.key }.associate { it.key to JsonPrimitive(it.value) }) })
        Response(body = json.toString().encodeToByteArray())
    }
}
