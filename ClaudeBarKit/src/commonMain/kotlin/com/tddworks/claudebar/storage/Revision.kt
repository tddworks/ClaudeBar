package com.tddworks.claudebar.storage

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * One aggregate's change counter. Every bump also moves [any], the one signal the UI follows
 * (MODULAR_DESIGN §5): logins, configurations and guest passes come and go while the app runs,
 * so no list made at start could name them all.
 */
internal class Revision {
    private val changes = MutableStateFlow(0L)

    /** Bumped after every change to this aggregate. */
    val flow: StateFlow<Long> = changes.asStateFlow()

    fun bump() {
        changes.update { it + 1 }
        anyChange.update { it + 1 }
    }

    companion object {
        private val anyChange = MutableStateFlow(0L)

        /** Bumped after any aggregate's change. */
        val any: StateFlow<Long> = anyChange.asStateFlow()
    }
}
