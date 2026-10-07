package com.tddworks.claudebar.datasources.process

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * #204 through the executor boundary: a background refresh's low priority must reach the CLIs
 * it starts, even though the terminal run leaves the caller's thread for `Dispatchers.IO`.
 */
class FetchQualityOfServiceTest {
    @Test
    fun `should run a CLI at the priority of the refresh that asked for it (#204)`() = runBlocking {
        withContext(FetchContext(QualityOfService.UTILITY)) {
            assertEquals(QualityOfService.UTILITY, InteractiveRunner.qualityOfService(InteractiveRunner.Options()))
        }
    }

    @Test
    fun `should run a CLI at default priority when no refresh set one`() = runBlocking {
        assertEquals(QualityOfService.DEFAULT, InteractiveRunner.qualityOfService(InteractiveRunner.Options()))
    }

    @Test
    fun `should run a CLI at an explicitly given priority over the refresh's`() = runBlocking {
        withContext(FetchContext(QualityOfService.UTILITY)) {
            val options = InteractiveRunner.Options(qualityOfService = QualityOfService.USER_INITIATED)

            assertEquals(QualityOfService.USER_INITIATED, InteractiveRunner.qualityOfService(options))
        }
    }

    @Test
    fun `should keep a background refresh's low priority once the CLI work leaves the async pool (#204)`() = runBlocking {
        val captured = withContext(FetchContext(QualityOfService.UTILITY)) {
            withContext(Dispatchers.IO) { currentQualityOfService() }
        }

        assertEquals(QualityOfService.UTILITY, captured)
    }

    @Test
    fun `should lose a background refresh's priority if it were read only after leaving the async pool (#204)`() = runBlocking {
        // Why the executor reads the priority inside the refresh: work started outside it — a
        // scope of its own, as a plain thread would be — sees the default.
        val observed = withContext(FetchContext(QualityOfService.UTILITY)) {
            CoroutineScope(Dispatchers.Default).async { currentQualityOfService() }.await()
        }

        assertEquals(QualityOfService.DEFAULT, observed)
    }
}
