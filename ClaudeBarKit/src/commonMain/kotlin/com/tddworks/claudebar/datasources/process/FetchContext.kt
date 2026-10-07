package com.tddworks.claudebar.datasources.process

import kotlinx.coroutines.currentCoroutineContext
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

/** How urgently the CLIs a fetch starts may use the Mac — Foundation's classes, by name. */
internal enum class QualityOfService { USER_INTERACTIVE, USER_INITIATED, DEFAULT, UTILITY, BACKGROUND }

/**
 * The quality of service for the CLIs a fetch starts, carried in the coroutine context so
 * the background loop can run them at a low priority without a parameter through every
 * fetch (#204): `withContext(FetchContext(QualityOfService.UTILITY)) { refresh() }`. On Apple
 * Silicon a lowered class keeps the spawned tree on efficiency cores, cutting idle heat.
 * Unlike a Swift task local, it travels with the coroutine onto `Dispatchers.IO`.
 */
internal class FetchContext(val qualityOfService: QualityOfService) : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<FetchContext>
}

/** The quality of service the running fetch asked for; `DEFAULT` when none did. */
internal suspend fun currentQualityOfService(): QualityOfService =
    currentCoroutineContext()[FetchContext]?.qualityOfService ?: QualityOfService.DEFAULT
