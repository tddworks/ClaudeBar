package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_BLOB
import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_DONE
import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_NULL
import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_OK
import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_OPEN_READONLY
import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_ROW
import cnames.structs.sqlite3
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_busy_timeout
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_close
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_column_blob
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_column_bytes
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_column_count
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_column_name
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_column_text
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_column_type
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_finalize
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_open_v2
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_prepare_v2
import cnames.structs.sqlite3_stmt
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_stmt_readonly
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_step
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.readBytes
import kotlinx.cinterop.toKString
import kotlinx.cinterop.value

/**
 * macOS's own libsqlite3, every database opened `SQLITE_OPEN_READONLY` and every statement
 * checked with `sqlite3_stmt_readonly` before it steps, so a definition can never change
 * another app's data.
 */
@OptIn(ExperimentalForeignApi::class)
internal class SystemSQLite : SQLiteReading {
    override fun rows(path: String, query: String, name: String, limit: Int): List<Map<String, StoredValue>> = memScoped {
        val handle = alloc<CPointerVar<sqlite3>>()
        if (sqlite3_open_v2(path, handle.ptr, SQLITE_OPEN_READONLY, null) != SQLITE_OK) {
            sqlite3_close(handle.value)
            throw UsageError.ExecutionFailed("Couldn't open $name")
        }
        val database = handle.value
        try {
            sqlite3_busy_timeout(database, 1000)
            val prepared = alloc<CPointerVar<sqlite3_stmt>>()
            if (sqlite3_prepare_v2(database, query, -1, prepared.ptr, null) != SQLITE_OK) {
                throw UsageError.ExecutionFailed("Couldn't query $name")
            }
            val statement = prepared.value
            try {
                if (sqlite3_stmt_readonly(statement) == 0) throw UsageError.ExecutionFailed("ClaudeBar may only read $name")
                val rows = mutableListOf<Map<String, StoredValue>>()
                while (rows.size < limit) {
                    val step = sqlite3_step(statement)
                    if (step == SQLITE_DONE) break
                    if (step != SQLITE_ROW) throw UsageError.ExecutionFailed("Couldn't query $name")
                    rows += row(statement)
                }
                rows
            } finally {
                sqlite3_finalize(statement)
            }
        } finally {
            sqlite3_close(database)
        }
    }

    private fun row(statement: CPointer<sqlite3_stmt>?): Map<String, StoredValue> {
        val row = mutableMapOf<String, StoredValue>()
        for (index in 0 until sqlite3_column_count(statement)) {
            val type = sqlite3_column_type(statement, index)
            val column = sqlite3_column_name(statement, index)?.toKString() ?: continue
            if (type == SQLITE_NULL) continue
            row[column] = if (type == SQLITE_BLOB) {
                val bytes = sqlite3_column_blob(statement, index)
                val size = sqlite3_column_bytes(statement, index)
                StoredValue.Bytes(if (bytes == null || size == 0) ByteArray(0) else bytes.readBytes(size))
            } else {
                val text = sqlite3_column_text(statement, index)
                val size = sqlite3_column_bytes(statement, index)
                StoredValue.Text(if (text == null || size == 0) "" else text.readBytes(size).decodeToString())
            }
        }
        return row
    }
}
