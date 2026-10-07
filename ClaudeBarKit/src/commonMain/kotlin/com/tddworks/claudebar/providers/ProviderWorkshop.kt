package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DataSourceError
import com.tddworks.claudebar.datasources.DataSources
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SecretStore
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.quotas.UsageError
import com.tddworks.claudebar.quotas.UsageSnapshot
import kotlin.coroutines.cancellation.CancellationException

/**
 * *Add Provider* and *Import* (USER_JOURNEYS F9, F10): a draft or a shared file tried before
 * anything is saved, then saved — the definition to the catalog, its keys to the vault, the
 * provider to the lineup. Every command answers with a value; nothing it tries is kept.
 */
public class ProviderWorkshop internal constructor(
    private val providers: Providers,
    private val catalog: ProviderCatalog,
    private val builtIns: BuiltInDefinitions,
    private val connections: DataSources,
    private val vault: SecretVault,
) {
    /** What *Copy from* offers: every built-in and every provider the person made. */
    public val templates: List<ProviderDefinition> get() = builtIns.all.values.toList() + catalog.custom()

    /** What a shared file would do, shown before anything is saved or run. */
    public fun review(file: String): Outcome<ImportReview> = outcome { catalog.review(file) }

    /** *Test Connection* for a draft, with the key typed so far. */
    public suspend fun testConnection(draft: ProviderDraft, key: String): ConnectionOutcome =
        test({ draft.connection() }, DRAFT_ID, typed { key })

    /** *Test Connection* for a shared file, with the keys typed in its review. */
    public suspend fun testConnection(review: ImportReview, keys: Map<String, String>): ConnectionOutcome {
        val definition = review.definition
        return test({ definition.dataSource(definition.defaultDataSource) ?: throw UsageError.NoData }, definition.id, typed { keys[it] })
    }

    /** What the draft would show for [response]: its usage, what it still needs, or the step that failed. */
    public fun preview(draft: ProviderDraft, response: Response): DraftPreview = try {
        val definition = draft.previewDefinition()
        DraftPreview.Usage(connections.make(definition.dataSources.first(), DRAFT_ID, scripts = builtIns::script).read(response))
    } catch (missing: ProviderDraft.Missing) {
        DraftPreview.Incomplete(missing.message ?: missing.toString())
    } catch (failure: Exception) {
        DraftPreview.Failed(DataSourceError.wrap(failure, DataSourceError.Step.MAPPING))
    }

    /** *Add*: the draft saved under a new id, its key in the vault, the provider in the lineup. */
    public fun add(draft: ProviderDraft, key: String): Outcome<Provider> = outcome {
        val definition = draft.definition(catalog.mintId(draft.name))
        val provider = providers.add(definition).orThrow()
        if (key.isNotEmpty()) vault.save(key, KEY_SETTING, provider.id)
        provider
    }

    /** *Add* after a review: what it showed, saved, with the keys typed for it. */
    public fun import(review: ImportReview, keys: Map<String, String>): Outcome<Provider> = outcome {
        val provider = providers.import(review).orThrow()
        for ((name, value) in keys) if (value.isNotEmpty()) vault.save(value, name, provider.id)
        provider
    }

    private suspend fun test(source: () -> DataSourceDefinition, providerId: String, secrets: SecretStore): ConnectionOutcome = try {
        val live = connections.make(source(), providerId, secrets, builtIns::script)
        ConnectionOutcome.Answered(live.fetchResponse())
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        ConnectionOutcome.Failed(DataSourceError.wrap(failure, DataSourceError.Step.FETCH))
    }

    private fun typed(value: (String) -> String?): SecretStore = object : SecretStore {
        override fun secret(name: String, provider: String): String? = value(name)?.takeIf { it.isNotEmpty() }
    }

    private fun <T> Outcome<T>.orThrow(): T = when (this) {
        is Outcome.Done -> value
        is Outcome.Refused -> throw IllegalStateException(reason)
    }

    internal companion object {
        const val DRAFT_ID = "draft"
        const val KEY_SETTING = "apiKey"
    }
}

/** What a draft would show for an answer, before it is saved. */
public sealed class DraftPreview {
    public data class Usage(val usage: UsageSnapshot) : DraftPreview()

    /** The draft still lacks something: [reason] says what. */
    public data class Incomplete(val reason: String) : DraftPreview()

    public data class Failed(val error: DataSourceError) : DraftPreview()
}
