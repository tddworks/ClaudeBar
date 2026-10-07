package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.fetch.aws.AWSCredentials
import com.tddworks.claudebar.datasources.fetch.aws.SignatureV4
import com.tddworks.claudebar.datasources.fetch.aws.SigningRequest
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** The Darwin adapters against the real system — no server needed. */
class DarwinNetworkTest {
    @Test
    fun `should refuse to ask anyone but this Mac when certificates aren't checked`() = runBlocking {
        assertFailsWith<IllegalArgumentException> {
            insecureLocalhostNetworkClient().send(HttpCall("https://example.com/"))
        }
        Unit
    }

    @Test
    fun `should fail as a transport error when nothing listens on this Mac`() = runBlocking {
        // Port 9 (discard) is closed on a Mac: the connection is refused, not answered.
        assertFailsWith<Exception> { systemNetworkClient().send(HttpCall("http://127.0.0.1:9/", timeoutSeconds = 5.0)) }
        assertFailsWith<Exception> { insecureLocalhostNetworkClient(5.0).send(HttpCall("https://127.0.0.1:9/")) }
        Unit
    }

    @Test
    fun `should start today at local midnight`() {
        val now = 1_767_268_800.0
        val start = startOfLocalDaySeconds(now)
        assertTrue(start <= now && now - start < 86_400 + 3_600, "$start")
        assertEquals(start, startOfLocalDaySeconds(start))
    }

    @Test
    fun `should sign with the same signature on the Mac as AWS's test suite`() {
        val signed = SignatureV4.sign(
            SigningRequest("GET", "example.amazonaws.com"),
            AWSCredentials("AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
            "us-east-1", "service", 1_440_938_160.0,
        )
        assertEquals("5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31", signed.signature)
    }
}
