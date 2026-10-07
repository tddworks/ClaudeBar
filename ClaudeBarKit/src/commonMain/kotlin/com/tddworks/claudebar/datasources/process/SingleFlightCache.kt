package com.tddworks.claudebar.datasources.process

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/**
 * Values by key, where callers that miss the same key at once wait for one computation.
 * Providers refresh in parallel; without this each spawns its own login shell to answer the
 * same `PATH` or `which` question. Lock-based, not suspending: the terminal runners ask from
 * plain threads. Distinct keys still compute in parallel.
 */
internal class SingleFlightCache<V>(private val now: () -> Double = ::monotonicSeconds) {
    private class Entry<V>(val value: V, val expiresAt: Double)

    private val lock = SynchronizedObject()
    private val entries = HashMap<String, Entry<V>>()
    /** One lock per key: holding it is being the one computation in flight. */
    private val inFlight = HashMap<String, SynchronizedObject>()

    /**
     * The cached value for [key], computed when absent or expired. [ttl] is asked of the new
     * value, so a "not found" can expire sooner than a hit.
     */
    fun value(key: String, ttl: (V) -> Double, compute: () -> V): V {
        fresh(key)?.let { return it.value }
        val flight = synchronized(lock) { inFlight.getOrPut(key) { SynchronizedObject() } }
        return synchronized(flight) {
            val waitedFor = fresh(key)
            if (waitedFor != null) return@synchronized waitedFor.value
            val value = compute()
            synchronized(lock) { entries[key] = Entry(value, now() + ttl(value)) }
            value
        }
    }

    /** Drops one key so the next lookup computes it again. */
    fun invalidate(key: String) = synchronized(lock) { entries.remove(key); Unit }

    /** Drops every entry; a computation in flight is unaffected. */
    fun invalidateAll() = synchronized(lock) { entries.clear() }

    private fun fresh(key: String): Entry<V>? = synchronized(lock) { entries[key]?.takeIf { it.expiresAt > now() } }
}
