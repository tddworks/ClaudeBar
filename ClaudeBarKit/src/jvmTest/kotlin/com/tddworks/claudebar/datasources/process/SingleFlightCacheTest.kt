package com.tddworks.claudebar.datasources.process

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class SingleFlightCacheTest {
    /** A clock the test moves. */
    private class Clock {
        var now = 0.0
    }

    @Test
    fun `should work out a value only once when it is asked for again`() {
        val cache = SingleFlightCache<Int>()
        val counter = AtomicInteger()

        val first = cache.value("k", ttl = { 60.0 }) { counter.incrementAndGet() }
        val second = cache.value("k", ttl = { 60.0 }) { counter.incrementAndGet() }

        assertEquals(1, first)
        assertEquals(1, second)
        assertEquals(1, counter.get())
    }

    @Test
    fun `should keep a separate value for each key`() {
        val cache = SingleFlightCache<String>()

        assertEquals("value-a", cache.value("a", ttl = { 60.0 }) { "value-a" })
        assertEquals("value-b", cache.value("b", ttl = { 60.0 }) { "value-b" })
    }

    @Test
    fun `should work the value out again once it has expired`() {
        val clock = Clock()
        val cache = SingleFlightCache<Int> { clock.now }
        val counter = AtomicInteger()

        val first = cache.value("k", ttl = { 0.05 }) { counter.incrementAndGet() }
        clock.now += 0.12
        val second = cache.value("k", ttl = { 0.05 }) { counter.incrementAndGet() }

        assertEquals(1, first)
        assertEquals(2, second)
    }

    @Test
    fun `should keep a found value longer than a missing one when the lifetime depends on the value`() {
        val clock = Clock()
        val cache = SingleFlightCache<Int?> { clock.now }
        val counter = AtomicInteger()
        // A miss expires soon, a hit lasts — the shape the locator relies on to retry missing tools sooner.
        val ttl: (Int?) -> Double = { if (it == null) 0.05 else 600.0 }

        assertNull(cache.value("k", ttl) { null })
        clock.now += 0.12

        assertEquals(1, cache.value("k", ttl) { counter.incrementAndGet() })
        assertEquals(1, cache.value("k", ttl) { counter.incrementAndGet() })
    }

    @Test
    fun `should work out again only the value that was forgotten`() {
        val cache = SingleFlightCache<Int>()
        val a = AtomicInteger()
        val b = AtomicInteger()

        cache.value("a", ttl = { 60.0 }) { a.incrementAndGet() }
        cache.value("b", ttl = { 60.0 }) { b.incrementAndGet() }
        cache.invalidate("a")

        assertEquals(2, cache.value("a", ttl = { 60.0 }) { a.incrementAndGet() })
        assertEquals(1, cache.value("b", ttl = { 60.0 }) { b.incrementAndGet() })
    }

    @Test
    fun `should work out every value again once all are forgotten`() {
        val cache = SingleFlightCache<Int>()
        val counter = AtomicInteger()

        cache.value("a", ttl = { 60.0 }) { counter.incrementAndGet() }
        cache.invalidateAll()
        cache.value("a", ttl = { 60.0 }) { counter.incrementAndGet() }

        assertEquals(2, counter.get())
    }

    @Test
    fun `should work a value out once when many ask for it at the same time`() {
        val cache = SingleFlightCache<Int>()
        val counter = AtomicInteger()
        val results = Collections.synchronizedList(mutableListOf<Int>())
        val start = CountDownLatch(1)

        // Real threads: the callers this protects are the terminal runners, on plain threads.
        val waiters = (0 until 16).map {
            thread {
                start.await()
                results += cache.value("shared", ttl = { 60.0 }) {
                    Thread.sleep(100) // widen the window so latecomers overlap
                    counter.incrementAndGet()
                }
            }
        }
        start.countDown()
        waiters.forEach { it.join() }

        assertEquals(1, counter.get())
        assertEquals(16, results.size)
        assertTrue(results.all { it == 1 })
    }
}
