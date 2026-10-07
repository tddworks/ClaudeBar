package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.DirectoryCall
import com.tddworks.claudebar.datasources.FileCall
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.Paths
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readByteArray
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** `file` — reads a file some tool keeps up to date. Ready while it exists. */
internal class FileFetcher(
    val call: FileCall,
    private val home: String,
    private val environment: (String) -> String?,
) : Fetching {
    private val path: String get() = Paths.resolve(call.path, home, environment)

    override fun isReady() = SystemFileSystem.exists(Path(path))

    override suspend fun fetch(credential: Credential?): Response {
        val data = runCatching { SystemFileSystem.source(Path(path)).buffered().use { it.readByteArray() } }.getOrNull()
            ?: throw UsageError.ExecutionFailed("No file at ${call.path}")
        return Response(body = data)
    }
}

/** `directory` — the matching names in a folder, sorted, hidden ones left out. Ready while the folder exists. */
internal class DirectoryFetcher(
    val call: DirectoryCall,
    private val home: String,
    private val environment: (String) -> String?,
) : Fetching {
    private val path: String get() = Paths.resolve(call.path, home, environment)

    override fun isReady() = SystemFileSystem.metadataOrNull(Path(path))?.isDirectory == true

    override suspend fun fetch(credential: Credential?): Response {
        val names = if (isReady()) runCatching { SystemFileSystem.list(Path(path)).map { it.name } }.getOrNull() else null
        names ?: throw UsageError.ExecutionFailed("No folder at ${call.path}")
        val match = call.match?.let { runCatching { Regex(it) }.getOrNull() }
        val entries = names.filter { name ->
            !name.startsWith(".") && (call.match == null || match?.containsMatchIn(name) == true)
        }.sorted()
        return Response(body = JsonObject(mapOf("entries" to JsonArray(entries.map(::JsonPrimitive)))).toString().encodeToByteArray())
    }
}
