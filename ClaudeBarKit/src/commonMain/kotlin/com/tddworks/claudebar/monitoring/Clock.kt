package com.tddworks.claudebar.monitoring

import kotlinx.coroutines.delay

/** Waits between background refreshes — injected so tests run the loop in virtual time. */
internal interface Clock {
    /** Suspends for [seconds]; cancelling the caller ends the wait. */
    suspend fun sleep(seconds: Double)
}

/** The real passing of time. */
internal object SystemClock : Clock {
    override suspend fun sleep(seconds: Double) = delay((seconds * 1000).toLong())
}
