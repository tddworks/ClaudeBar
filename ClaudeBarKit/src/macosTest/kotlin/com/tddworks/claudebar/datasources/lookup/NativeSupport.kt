package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.lookup.sqlite.SQLITE_OK
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_close
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_exec
import com.tddworks.claudebar.datasources.lookup.sqlite.sqlite3_open
import cnames.structs.sqlite3
import kotlinx.cinterop.CPointerVar
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.files.SystemTemporaryDirectory
import kotlinx.io.readByteArray
import platform.Foundation.NSDate
import platform.Foundation.NSFileManager
import platform.Foundation.NSFileModificationDate
import platform.Foundation.dateWithTimeIntervalSinceNow
import kotlin.random.Random

/** A fresh folder under the temporary directory, and a way to remove it. */
internal class Scratch {
    val root: String = Path(SystemTemporaryDirectory, "claudebar-lookup-${Random.nextLong().toULong()}").toString()

    init {
        SystemFileSystem.createDirectories(Path(root))
    }

    /** A database at [relative] under [root], made by running [sql] — a test's own writable connection. */
    @OptIn(ExperimentalForeignApi::class)
    fun database(sql: String, relative: String = "state.vscdb"): String {
        val path = "$root/$relative"
        SystemFileSystem.createDirectories(Path(path).parent!!)
        memScoped {
            val handle = alloc<CPointerVar<sqlite3>>()
            check(sqlite3_open(path, handle.ptr) == SQLITE_OK)
            check(sqlite3_exec(handle.value, sql, null, null, null) == SQLITE_OK) { "couldn't run $sql" }
            sqlite3_close(handle.value)
        }
        return path
    }

    fun bytes(path: String): ByteArray = SystemFileSystem.source(Path(path)).buffered().use { it.readByteArray() }

    fun changed(path: String, secondsAgo: Double) {
        NSFileManager.defaultManager.setAttributes(
            mapOf(NSFileModificationDate to NSDate.dateWithTimeIntervalSinceNow(-secondsAgo)), path, null,
        )
    }

    fun remove() {
        fun delete(path: Path) {
            if (SystemFileSystem.metadataOrNull(path)?.isDirectory == true) SystemFileSystem.list(path).forEach(::delete)
            SystemFileSystem.delete(path, mustExist = false)
        }
        delete(Path(root))
    }
}

/** Hex text of [bytes], for an SQL `X'…'` literal. */
internal fun hex(bytes: ByteArray) = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

/** UTF-16LE bytes of [text], the way some apps store it. */
internal fun utf16(text: String) = text.flatMap { listOf((it.code and 0xFF).toByte(), (it.code shr 8).toByte()) }.toByteArray()
