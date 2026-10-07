package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.logs.UsageLog
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/**
 * The context's factory: definition → [Provider], its data sources made live by the engine's
 * `DataSources`. The composition root makes one, with the [Engine] and the built-ins, and never
 * names a worker.
 */
internal class ProviderFactory(
    private val engine: Engine,
    val builtIns: BuiltInDefinitions,
    /** The custom definitions in use, found by lineup id after the built-ins. */
    val customs: CustomDefinitions = CustomDefinitions(),
) {
    /** A built-in definition, shipped beside the app. Throws `DefinitionError` for an unknown id. */
    fun builtIn(id: String): ProviderDefinition = builtIns.definition(id)

    /** The definition — built in, then custom — a lineup id belongs to. What screens that only hold an id use for a face. */
    fun definition(lineupId: String): ProviderDefinition? = builtIns.forLineupId(lineupId) ?: customs[lineupId]

    /** A provider of every definition, in the order given, on one engine. */
    fun make(definitions: List<ProviderDefinition>): List<Provider> = definitions.map(::make)

    /** A built-in provider by id. Throws `DefinitionError` for an unknown id. */
    fun make(id: String): Provider = make(builtIn(id))

    /**
     * A provider of the definition on the engine: its logins from settings, guest passes only
     * when it declares them. A definition from outside the bundle becomes findable by its lineup id.
     */
    fun make(definition: ProviderDefinition): Provider {
        if (definition.profile.origin != ProviderProfile.Origin.BUILT_IN) customs.register(definition)
        val id = definition.id
        val settings = engine.settings
        val cli = definition.cli ?: id
        val guestPasses = definition.guestPasses?.let { command ->
            engine.guestPasses?.let { run -> GuestPasses(run({ settings.cliPath(id) ?: cli }, command)) }
        }
        return Provider(
            definition = definition,
            settings = settings,
            saved = settings.accounts(id),
            makeDataSource = { source, login ->
                engine.connections.make(source, id, engine.vault?.scoped(login), builtIns::script)
            },
            guestPasses = guestPasses,
            // The definition says how to read each login's logs.
            usageHistory = definition.usageHistory?.let { history(it, id) },
            makeUsageHistory = ::history,
            folders = engine.folders,
            loginsInUse = engine.loginsInUse,
            vault = engine.vault,
            paths = engine.paths,
            isExecutable = engine.isExecutable,
            locate = engine.locate,
            signIn = engine.signIn,
            signInRoot = SignedInFolder.signInRoot(engine.home),
            now = engine.now,
        )
    }

    /** A login's usage history on this Mac, its closed days kept under its lineup id. */
    private fun history(definition: UsageLog.Definition, login: String): UsageHistory = UsageHistory(
        definition, login,
        log = { UsageLog.make(it, engine.home, engine.environment, builtIns::script, now = engine.now) },
        ledger = { key -> engine.ledger?.let { DayLedger(it, key) } },
    )
}

/**
 * The custom definitions in use — what [ProviderFactory.definition] finds after the built-ins.
 * Set when the app loads them, and on *Save* / *Delete*.
 */
internal class CustomDefinitions {
    private val lock = SynchronizedObject()
    private val definitions = mutableMapOf<String, ProviderDefinition>()

    fun register(definition: ProviderDefinition) {
        synchronized(lock) { definitions[definition.id] = definition }
    }

    fun unregister(id: String) {
        synchronized(lock) { definitions.remove(id) }
    }

    /** The custom definition a lineup id belongs to — `custom-x.<account>` belongs to `custom-x`. */
    operator fun get(lineupId: String): ProviderDefinition? =
        synchronized(lock) { definitions[lineupId] ?: definitions[lineupId.substringBefore('.')] }
}
