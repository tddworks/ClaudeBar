package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.MappingFacts
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.mapping.JavaScriptCoreEngine
import com.tddworks.claudebar.datasources.mapping.reader
import com.tddworks.claudebar.quotas.UsageSnapshot
import platform.Foundation.NSDate
import platform.Foundation.NSFileManager
import platform.Foundation.timeIntervalSince1970

/** The built-in definitions as the repo ships them, found from wherever the test runs. */
internal object RepoDefinitions {
    val builtIns: BuiltInDefinitions by lazy { BuiltInDefinitions(FolderDefinitionFiles(folder())) }

    private fun folder(): String {
        val relative = "Modules/Providers/Resources/Providers"
        var directory = NSFileManager.defaultManager.currentDirectoryPath
        repeat(8) {
            val candidate = "$directory/$relative"
            if (NSFileManager.defaultManager.fileExistsAtPath("$candidate/kimi.json")) return candidate
            directory = directory.substringBeforeLast('/', "")
        }
        return "../$relative"
    }

    /** A response read through a built-in definition's data source, as Swift's `DataSource.read` does: a failure is its `UsageError`. */
    fun read(id: String, kind: String, response: Response, providerId: String = id): UsageSnapshot {
        val source = builtIns.definition(id).dataSource(kind)!!
        val mapper = source.mapping.reader(builtIns::script, JavaScriptCoreEngine(), { NSDate().timeIntervalSince1970 })
        return try {
            mapper.read(response, MappingFacts(), providerId)
        } catch (error: Throwable) {
            throw DataSourceError.wrap(error, DataSourceError.Step.MAPPING).reason
        }
    }
}

/** Kimi's mappings read through its definition, as the old probes' fixtures were. */
internal object KimiDefinitionFixtures {
    fun read(response: Response, kind: String, providerId: String = "kimi"): UsageSnapshot =
        RepoDefinitions.read("kimi", kind, response, providerId)

    fun api(json: String, providerId: String): UsageSnapshot = read(Response(body = json.encodeToByteArray()), "api", providerId)

    fun cli(text: String): UsageSnapshot = read(Response(text), "cli")

    fun reset(text: String): Double? = runCatching { cli("Weekly limit 100% left (resets in $text)") }.getOrNull()?.quotas?.firstOrNull()?.resetsAtSeconds
}
