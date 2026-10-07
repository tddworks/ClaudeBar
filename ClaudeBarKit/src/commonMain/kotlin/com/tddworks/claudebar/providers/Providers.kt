package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.diagnostics.AppLog
import kotlinx.coroutines.flow.StateFlow

/**
 * *Providers* — the providers you keep: the Settings → Providers pane (TARGET §2.1). It
 * creates a custom provider, reads them and the lineup, keeps their order and deletes a custom
 * one. The Monitor holds it and only watches; a login added to a provider is the provider's own
 * business, never this collection's.
 */
internal class Providers(
    providers: List<Provider>,
    private val catalog: ProviderCatalog,
    private val settings: ProviderSettingsRepository? = null,
    private val vault: SecretVault? = null,
    /** Where a kept custom definition is found by its lineup id — the factory's. */
    private val customs: CustomDefinitions = CustomDefinitions(),
    /** Makes a definition live — the real connections in the app, stubbed ones in tests. */
    private val make: (ProviderDefinition) -> Provider,
) {
    private val state = ObservableState(ordered(providers.distinctBy { it.id }, settings?.providerOrder() ?: emptyList()))

    /** Bumped when a provider is added, moved or deleted. */
    val revision: StateFlow<Long> get() = state.revision

    /** Every provider, in the pane's order. */
    val all: List<Provider> get() = state.current

    // Read

    /** Every login of every provider, on or off, in the pane's order. */
    val logins: List<Account> get() = all.flatMap { it.accounts }

    /**
     * The enabled logins of enabled providers, in the pane's order — what the pills, the menu
     * bar, refreshes and alerts show. Derived, never kept.
     */
    val lineup: List<Account> get() = all.flatMap { provider -> provider.accounts.filter(provider::isInLineup) }

    fun provider(id: String): Provider? = all.firstOrNull { it.id == id }

    /** A login by its lineup id — `claude`, `codex.<acct>`. */
    fun login(id: String): Account? = logins.firstOrNull { it.id == id }

    /**
     * A login's product — found by the id the login names, null once it is gone. The way to ask
     * anything product-level about a login (TARGET §2.1: a login never refers to its provider).
     */
    fun provider(of: Account): Provider? = provider(of.providerId)

    // Create

    /** *Add Provider*: saves the definition, then keeps it after the others. */
    fun add(definition: ProviderDefinition): Outcome<Provider> = outcome {
        if (provider(definition.id) != null) throw DefinitionErrors.duplicateProvider(definition.id)
        catalog.add(definition)
        keep(definition)
    }

    /** *Import*: the reviewed definition, saved and kept like an added one. */
    fun import(review: ImportReview): Outcome<Provider> = outcome {
        val definition = catalog.import(review)
        if (provider(definition.id) != null) throw DefinitionErrors.duplicateProvider(definition.id)
        keep(definition)
    }

    private fun keep(definition: ProviderDefinition): Provider {
        customs.register(definition)
        val provider = make(definition)
        state.update { it + provider }
        AppLog.providers.info("Kept custom provider ${definition.id}")
        return provider
    }

    // Update: the order

    /** Moves a provider, its logins together, [offset] places; stops at either end. */
    fun move(id: String, offset: Int) {
        val all = all
        val index = all.indexOfFirst { it.id == id }
        if (offset == 0 || index < 0) return
        val newIndex = (index + offset).coerceIn(0, all.size - 1)
        if (newIndex == index) return
        state.update { providers -> providers.toMutableList().also { it.add(newIndex, it.removeAt(index)) } }
        settings?.setProviderOrder(logins.map { it.id })
    }

    // Delete

    /** Deletes a provider you made: its file, its keys and its place. A built-in or an extension is never deleted — it is turned off. */
    fun remove(id: String): Outcome<Unit> = outcome {
        val provider = provider(id) ?: return@outcome
        if (provider.definition.profile.origin != ProviderProfile.Origin.CUSTOM) throw DefinitionErrors.notDeletable(id)
        catalog.remove(id)
        for (setting in provider.definition.settings) {
            if (setting.kind != Setting.Kind.Secret) continue
            for (login in provider.accounts) vault?.delete(setting.id, login.id)
        }
        customs.unregister(id)
        state.update { providers -> providers.filterNot { it.id == id } }
        AppLog.providers.info("Deleted custom provider $id")
    }

    private companion object {
        /** The saved order is by login id; a provider goes where its first login is named, one it doesn't name keeps its place after those it does. */
        fun ordered(providers: List<Provider>, order: List<String>): List<Provider> {
            if (order.isEmpty()) return providers
            val rank = mutableMapOf<String, Int>()
            order.forEachIndexed { index, id -> rank.getOrPut(id) { index } }
            return providers.withIndex()
                .sortedBy { (offset, provider) -> provider.accounts.mapNotNull { rank[it.id] }.minOrNull() ?: (order.size + offset) }
                .map { it.value }
        }
    }
}
