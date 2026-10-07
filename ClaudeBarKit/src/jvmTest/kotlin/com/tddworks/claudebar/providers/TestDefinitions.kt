package com.tddworks.claudebar.providers

import java.io.File
import java.nio.file.Files

/** The definitions the app ships, read from the repository as the bundle holds them. */
object TestDefinitions {
    const val FOLDER = "../Modules/Providers/Resources/Providers"

    internal val builtIns = BuiltInDefinitions(FolderDefinitionFiles(FOLDER))

    internal fun builtIn(id: String): ProviderDefinition = builtIns.definition(id)

    /** A new, empty folder for one test. */
    fun folder(prefix: String = "providers"): File = Files.createTempDirectory(prefix).toFile()

    /** `docs/features/extensions/example-provider`, the extension the docs show. */
    val exampleExtension = File("../docs/features/extensions/example-provider")
}
