package com.tddworks.claudebar.providers

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * An aggregate's observable state, replaced whole under one lock, and the revision the UI
 * re-reads after every change (MODULAR_DESIGN §5) — what Swift's `@Observable` on the main
 * actor gave, safe from any thread.
 */
internal class ObservableState<T>(initial: T) {
    private val lock = SynchronizedObject()
    private var value: T = initial
    private val changes = MutableStateFlow(0L)

    /** Bumped after every change. */
    val revision: StateFlow<Long> = changes.asStateFlow()

    val current: T get() = synchronized(lock) { value }

    /** Replaces the state with [transform] of it, atomically, and bumps the revision. */
    fun update(transform: (T) -> T): T {
        val updated = synchronized(lock) { transform(value).also { value = it } }
        changes.update { it + 1 }
        return updated
    }
}
