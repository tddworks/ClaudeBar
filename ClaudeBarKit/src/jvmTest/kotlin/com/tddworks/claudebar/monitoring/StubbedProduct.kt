package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.providers.CustomDefinitions
import com.tddworks.claudebar.providers.InMemoryProviderSettings
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.ProviderCatalog
import com.tddworks.claudebar.providers.ProviderDefinition
import com.tddworks.claudebar.providers.ProviderProfile
import com.tddworks.claudebar.providers.ProviderSettingsRepository
import com.tddworks.claudebar.providers.Providers
import com.tddworks.claudebar.providers.StubbedProvider
import com.tddworks.claudebar.providers.TestDefinitions
import com.tddworks.claudebar.quotas.QuotaStatus
import com.tddworks.claudebar.quotas.UsageError
import java.io.File
import java.time.Instant
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger

// What the Monitor's suites stand on: real `Provider`s from a one-source definition, their
// connection stubbed to answer what a test says (TARGET §7). Only the identity matters here;
// each real provider is tested end to end in the providers suites.

/** One quota as ClaudeBar's own usage JSON gives it: `session`, `weekly`, `model:<name>`. */
internal data class StubQuota(val type: String, val percentRemaining: Double, val resetsInSeconds: Double? = null)

/** What a stubbed product's connection answers each time it is asked — quotas, or a failure — and how often it was asked. */
internal class StubUsage(private val answer: (asked: Int) -> List<StubQuota>) {
    private val asked = AtomicInteger()

    /** How many times the provider fetched. */
    val count: Int get() = asked.get()

    fun json(): String {
        val quotas = answer(asked.incrementAndGet()).joinToString(",") { quota ->
            val reset = quota.resetsInSeconds?.let {
                val at = Instant.ofEpochSecond((System.currentTimeMillis() / 1000.0 + it).toLong())
                ""","resetsAt":"$at""""
            } ?: ""
            """{"type":"${quota.type}","percentRemaining":${quota.percentRemaining}$reset}"""
        }
        return """{"quotas":[$quotas]}"""
    }

    companion object {
        /** Answers [quotas] every time. */
        fun of(vararg quotas: StubQuota) = StubUsage { quotas.toList() }

        /** One session quota, a point lower each time it is asked: 99%, 98% … */
        fun counting() = StubUsage { listOf(StubQuota("session", 100.0 - it)) }

        /** Never answers: every fetch times out. */
        fun failing() = StubUsage { throw UsageError.Timeout }

        /** Never asked in the test. */
        fun unused() = StubUsage { emptyList() }
    }
}

/** The products and stubs a test made, removed when it ends. */
internal class StubbedProducts {
    private val stubs = Collections.synchronizedList(mutableListOf<StubbedProvider>())
    private val folder: File = TestDefinitions.folder("monitor")

    /**
     * A product whose one data source answers [usage] — ready unless not [available]; named
     * [name], else its id capitalised.
     */
    fun product(
        id: String,
        usage: StubUsage = StubUsage.unused(),
        settings: InMemoryProviderSettings = InMemoryProviderSettings(),
        available: Boolean = true,
        name: String? = null,
    ): Provider {
        val definition = ProviderDefinition.parse(
            """
            {"profile":{"id":"$id","name":"${name ?: id.replaceFirstChar { it.uppercase() }}","links":{}},
             "dataSources":[{"kind":"stub","credential":{"environment":"STUB_READY"},
                             "fetch":{"http":{"url":"https://stub.invalid/$id"}},"mapping":{"usage":{}}}],
             "defaultDataSource":"stub"}
            """,
            ProviderProfile.Origin.CUSTOM,
        )
        val network = object : NetworkClient {
            override suspend fun send(call: HttpCall): Response = Response(200, emptyMap(), usage.json().encodeToByteArray())
        }
        val stub = StubbedProvider(network = network).also { stubs += it }
        stub.environment = if (available) mapOf("STUB_READY" to "ready") else emptyMap()
        return stub.make(definition, settings = settings)
    }

    /** The providers a test keeps, in order. */
    fun kept(products: List<Provider>, settings: ProviderSettingsRepository? = null): Providers = Providers(
        products,
        ProviderCatalog(TestDefinitions.builtIns, File(folder, "providers").path, File(folder, "extensions").path),
        settings,
        customs = CustomDefinitions(),
        make = { error("tests don't add providers") },
    )

    fun cleanUp() {
        stubs.forEach { it.cleanUp() }
        folder.deleteRecursively()
    }
}

/** An alerter that keeps what it was told — tests assert on it. */
internal class RecordingAlerter : QuotaAlerter {
    data class Alert(val providerId: String, val previous: QuotaStatus, val current: QuotaStatus)

    val alerts: MutableList<Alert> = Collections.synchronizedList(mutableListOf())

    override suspend fun requestPermission(): Boolean = true

    override suspend fun alert(providerId: String, previousStatus: QuotaStatus, currentStatus: QuotaStatus) {
        alerts += Alert(providerId, previousStatus, currentStatus)
    }
}
