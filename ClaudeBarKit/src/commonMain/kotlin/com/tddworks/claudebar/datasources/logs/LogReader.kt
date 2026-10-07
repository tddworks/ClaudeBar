package com.tddworks.claudebar.datasources.logs

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readByteArray

/** The reader for a log's `format` — one per case of the closed list. */
internal sealed class LogReader {
    class JsonLines(val reader: JSONLinesReader) : LogReader()
    class Json(val reader: JSONLogReader) : LogReader()

    /** Records from [files], in file order. */
    suspend fun records(files: List<String>): List<LogRecord> = when (this) {
        is JsonLines -> reader.records(files)
        is Json -> reader.records(files)
    }

    /** What the last scan did — only a reader that keeps files between scans can say. */
    suspend fun lastScan(): JSONLinesReader.ScanSummary = when (this) {
        is JsonLines -> reader.lastScan()
        is Json -> JSONLinesReader.ScanSummary()
    }

    companion object {
        fun of(records: UsageLog.Records): LogReader = when (records.format) {
            UsageLog.Format.JSON_LINES -> JsonLines(JSONLinesReader(records))
            UsageLog.Format.JSON -> Json(JSONLogReader(records))
        }
    }
}

/**
 * `json` — one JSON document per file, one record each: a session's summary, written whole.
 * Small files, so each scan reads them again. A file is read by the first shape whose
 * `where` holds, as a line is.
 */
internal class JSONLogReader(records: UsageLog.Records) {
    private val shapes = records.shapes.map(::RecordShape)

    fun records(files: List<String>): List<LogRecord> = files.mapNotNull { path ->
        val bytes = runCatching { SystemFileSystem.source(Path(path)).buffered().use { it.readByteArray() } }.getOrNull()
        bytes?.let(::jsonDocument)?.let { shapes.record(it, path) }
    }
}
