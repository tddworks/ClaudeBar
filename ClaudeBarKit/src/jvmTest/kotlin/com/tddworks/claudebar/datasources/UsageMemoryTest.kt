package com.tddworks.claudebar.datasources

import com.tddworks.claudebar.quotas.QuotaType
import com.tddworks.claudebar.quotas.UsageError
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * A data source's memory between refreshes — the cached usage (`cache.ttl`) and a rate limit's
 * end — seen through `fetchUsage()`.
 */
class UsageMemoryTest {
    /** A clock a test moves forward. */
    private var now = TEST_NOW

    private fun source(cache: String?, network: NetworkClient): DataSource {
        val cacheJson = cache?.let { ""","cache":$it""" } ?: ""
        val definition = definition("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}}$cacheJson,
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """)
        return testDataSources(network = network, now = { now }).make(definition, "test")
    }

    private fun ok(body: String) = Response(200, body = body.encodeToByteArray())

    /** Answers the n-th request with `n * 10` percent used. */
    private fun counting(): NetworkClient {
        var calls = 0
        return AnsweringNetwork {
            calls += 1
            ok("""{"used":${calls * 10}}""")
        }
    }

    @Test
    fun `should show the remembered usage without asking again within the cache time`() = runTest {
        val source = source("""{"ttl":60}""", counting())

        val first = source.fetchUsage()
        now += 59
        val second = source.fetchUsage()

        assertEquals(60.0, source.cacheTTL)
        assertEquals(90.0, first.quota(QuotaType.Weekly)?.percentRemaining)
        assertEquals(90.0, second.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should ask again once the remembered usage is older than the cache time`() = runTest {
        val source = source("""{"ttl":60}""", counting())

        source.fetchUsage()
        now += 60
        val second = source.fetchUsage()

        assertEquals(80.0, second.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should ask every time when the cache time is zero`() = runTest {
        val source = source("""{"ttl":0}""", counting())

        source.fetchUsage()
        val second = source.fetchUsage()

        assertEquals(80.0, second.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should ask every time when the data source keeps no cache`() = runTest {
        val source = source(null, counting())

        source.fetchUsage()
        val second = source.fetchUsage()

        assertNull(source.cacheTTL)
        assertEquals(80.0, second.quota(QuotaType.Weekly)?.percentRemaining)
    }

    @Test
    fun `should not ask again until a rate limit ends`() = runTest {
        var calls = 0
        // Throttled once; any later request would succeed.
        val network = AnsweringNetwork {
            calls += 1
            if (calls == 1) Response(429, mapOf("Retry-After" to "120"), ByteArray(0)) else ok("""{"used":25}""")
        }
        val source = source(null, network)
        val limited = DataSourceError(DataSourceError.Step.FETCH, UsageError.RateLimited(now + 120))

        assertEquals(limited, thrown { source.fetchUsage() })
        now += 119
        assertEquals(limited, thrown { source.fetchUsage() })
        now += 1
        val usage = source.fetchUsage()

        assertEquals(75.0, usage.quota(QuotaType.Weekly)?.percentRemaining)
    }
}
