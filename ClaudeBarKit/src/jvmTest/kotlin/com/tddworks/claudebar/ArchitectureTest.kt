package com.tddworks.claudebar

import com.lemonappdev.konsist.api.Konsist
import com.lemonappdev.konsist.api.provider.KoNameProvider
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import java.io.File

/** The package rules of docs/architecture/MODULAR_DESIGN.md §3, read from the sources. */
class ArchitectureTest {
    private val root = "com.tddworks.claudebar"

    /** What each package may use — §3's arrows. `diagnostics` is open to all; `kit` wires everything. */
    private val mayUse = mapOf(
        "quotas" to setOf(),
        "diagnostics" to setOf(),
        "datasources" to setOf("quotas"),
        "providers" to setOf("datasources", "quotas"),
        "storage" to setOf("providers", "datasources", "quotas"),
        "monitoring" to setOf("providers", "quotas"),
        "alerting" to setOf("providers", "quotas"),
        "activity" to setOf("providers", "quotas"),
        "leaderboard" to setOf("providers", "quotas"),
        "kit" to setOf("quotas", "datasources", "providers", "storage", "monitoring", "alerting", "activity", "leaderboard"),
    )

    /** Vendor words already in the kernel, each with the shape that removes it. */
    private val interimVendorNames = mapOf(
        "ClaudeMax" to "AccountTier → Plan (CANONICAL_MODEL §6)",
        "ClaudePro" to "AccountTier → Plan (CANONICAL_MODEL §6)",
        "ClaudeApi" to "AccountTier → Plan (CANONICAL_MODEL §6)",
    )

    private val production = Konsist.scopeFromProduction()

    private fun contextOf(packageName: String): String? =
        packageName.removePrefix("$root.").takeIf { packageName.startsWith("$root.") }?.substringBefore('.')

    @Test
    fun `should keep every source in a package the design names`() {
        val unknown = production.files
            .map { it.packagee?.name.orEmpty() }
            .filter { contextOf(it) !in mayUse.keys }
            .distinct()
        assertEquals(emptyList<String>(), unknown)
    }

    @Test
    fun `should use only the packages the design's arrows allow`() {
        val violations = production.files.flatMap { file ->
            val from = contextOf(file.packagee?.name.orEmpty()) ?: return@flatMap emptyList()
            file.imports.mapNotNull { import ->
                val to = contextOf(import.name) ?: return@mapNotNull null
                val allowed = to == from || to == "diagnostics" || to in mayUse[from].orEmpty()
                if (allowed) null else "${file.name}: $from uses $to (${import.name})"
            }
        }
        assertEquals(emptyList<String>(), violations)
    }

    @Test
    fun `should give every public type a name no other package uses`() {
        val topLevel: List<KoNameProvider> = production.classes(includeNested = false) +
            production.interfaces(includeNested = false) +
            production.objects(includeNested = false)
        val repeated = topLevel.groupBy { it.name }.filterValues { it.size > 1 }.keys.sorted()
        assertEquals(emptyList<String>(), repeated, "Swift sees one flat namespace; repeats become Name_")
    }

    @Test
    fun `should name no vendor outside the definitions`() {
        val vendors = File("../Modules/Providers/Resources/Providers").listFiles().orEmpty()
            .map { it.name.substringBefore('.').substringBefore('-').lowercase() }
            .toSet()
        val names = production.classes() + production.interfaces() + production.objects() +
            production.functions() + production.properties()
        val violations = names.map { it.name }.distinct().filter { name ->
            name !in interimVendorNames &&
                name.replace("ClaudeBar", "").split(Regex("(?<=[a-z0-9])(?=[A-Z])|_"))
                    .any { it.lowercase() in vendors }
        }
        assertEquals(emptyList<String>(), violations)
    }
}
